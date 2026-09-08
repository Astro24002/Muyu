from __future__ import annotations

import hashlib
import json
import secrets
from collections.abc import Callable
from datetime import datetime, timedelta, timezone
from typing import TYPE_CHECKING
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth.service import SmsAuthError, normalize_phone as normalize_auth_phone
from app.auth.profile import public_display_name
from app.db.enums import ApprovalStatus, BootstrapState, DeviceStatus, InviteStatus, MembershipStatus
from app.db.models import (
    AndroidDevice,
    DeviceAuthorizationRequest,
    IdempotencyRecord,
    User,
    Workspace,
    WorkspaceCursor,
    WorkspaceInvite,
    WorkspaceMembership,
)
from app.tasks.operations import request_fingerprint
from app.workspaces.bootstrap_schemas import (
    BootstrapDevice,
    BootstrapInvite,
    BootstrapPayload,
    BootstrapWorkspace,
    match_status_for_member_count,
    public_device_status,
)
from app.workspaces.service import WorkspaceConflict

if TYPE_CHECKING:
    from app.auth.dependencies import MobilePrincipal


_BIND_ROUTE = "/api/v1/workspaces/bind-partner"
_IDEMPOTENCY_TTL = timedelta(days=7)


class WorkspaceBootstrapService:
    """Transactional first-login and two-person workspace onboarding."""

    def __init__(
        self,
        session: Session,
        *,
        now: Callable[[], datetime] = lambda: datetime.now(timezone.utc),
        approval_ttl_seconds: int = 600,
    ) -> None:
        self.session = session
        self.now = now
        self.approval_ttl_seconds = min(900, max(60, approval_ttl_seconds))

    def get_state(self, principal: MobilePrincipal) -> BootstrapPayload:
        return self._state_for_user(principal.user_id, principal.device_id)

    def bind_partner(self, actor_user_id: UUID, phone: str, request_id: UUID) -> BootstrapPayload:
        actor = self.session.scalar(select(User).where(User.id == actor_user_id).with_for_update())
        if actor is None or actor.status.value != "ACTIVE":
            raise WorkspaceConflict("authentication_required", "user does not exist")

        normalized = _normalize_phone(phone)
        fingerprint = request_fingerprint(_BIND_ROUTE, {"phone": normalized})
        existing = self.session.scalar(
            select(IdempotencyRecord)
            .where(
                IdempotencyRecord.actor_user_id == actor_user_id,
                IdempotencyRecord.request_id == request_id,
                IdempotencyRecord.route == _BIND_ROUTE,
            )
            .with_for_update()
        )
        if existing is not None:
            return self._replay(existing, fingerprint)

        existing_membership = self.session.scalar(
            select(WorkspaceMembership)
            .where(
                WorkspaceMembership.user_id == actor_user_id,
                WorkspaceMembership.status == MembershipStatus.ACTIVE,
            )
            .with_for_update()
        )
        if existing_membership is not None:
            raise WorkspaceConflict("workspace_limit_reached", "user already belongs to a workspace")
        if normalized == actor.phone:
            raise WorkspaceConflict("partner_phone_must_differ", "partner phone must differ from actor phone")

        partner = self.session.scalar(select(User).where(User.phone == normalized).with_for_update())
        if partner is not None:
            partner_membership = self.session.scalar(
                select(WorkspaceMembership).where(
                    WorkspaceMembership.user_id == partner.id,
                    WorkspaceMembership.status == MembershipStatus.ACTIVE,
                )
            )
            if partner_membership is not None:
                raise WorkspaceConflict("partner_already_bound", "partner already belongs to a workspace")

        now = self.now()
        workspace = Workspace()
        self.session.add(workspace)
        self.session.flush()
        self.session.add(
            WorkspaceMembership(
                workspace_id=workspace.id,
                user_id=actor_user_id,
                member_slot=1,
                status=MembershipStatus.ACTIVE,
                joined_at=now,
            )
        )
        self.session.add(WorkspaceCursor(workspace_id=workspace.id, next_cursor=1))
        invite = WorkspaceInvite(
            workspace_id=workspace.id,
            inviter_user_id=actor_user_id,
            invited_phone=normalized,
            status=InviteStatus.PENDING,
            expires_at=now + _IDEMPOTENCY_TTL,
        )
        self.session.add(invite)
        self.session.flush()

        payload = self._state_for_user(actor_user_id, self._current_device_id(actor_user_id))
        self._save_idempotency(
            workspace_id=workspace.id,
            actor_user_id=actor_user_id,
            request_id=request_id,
            route=_BIND_ROUTE,
            fingerprint=fingerprint,
            status_code=201,
            payload=payload,
            expires_at=invite.expires_at,
        )
        return payload

    def accept_invite(self, invite_id: UUID, user_id: UUID, device_id: UUID, request_id: UUID) -> BootstrapPayload:
        invite = self.session.scalar(
            select(WorkspaceInvite).where(WorkspaceInvite.id == invite_id).with_for_update()
        )
        if invite is None:
            raise WorkspaceConflict("not_found", "invite not found")
        workspace = self.session.scalar(
            select(Workspace).where(Workspace.id == invite.workspace_id).with_for_update()
        )
        if workspace is None:
            raise WorkspaceConflict("not_found", "workspace not found")

        route = f"/api/v1/workspace-invites/{invite_id}/accept"
        fingerprint = request_fingerprint(route, {"device_id": str(device_id)})
        existing = self.session.scalar(
            select(IdempotencyRecord)
            .where(
                IdempotencyRecord.workspace_id == workspace.id,
                IdempotencyRecord.request_id == request_id,
                IdempotencyRecord.route == route,
            )
            .with_for_update()
        )
        if existing is not None:
            if existing.actor_user_id != user_id:
                raise WorkspaceConflict("idempotency_key_reused", "request id was used by another user")
            return self._replay(existing, fingerprint)

        user = self.session.scalar(select(User).where(User.id == user_id).with_for_update())
        device = self.session.scalar(select(AndroidDevice).where(AndroidDevice.id == device_id).with_for_update())
        if user is None or device is None:
            raise WorkspaceConflict("not_found", "invite or candidate device not found")
        if device.user_id != user_id:
            raise WorkspaceConflict("approval_not_allowed", "candidate device does not belong to this user")
        if user.phone != invite.invited_phone:
            raise WorkspaceConflict("approval_not_allowed", "invite does not match this user")
        if invite.status != InviteStatus.PENDING:
            raise WorkspaceConflict("lifecycle_conflict", "invite is no longer pending")
        now = self.now()
        if invite.expires_at <= now:
            invite.status = InviteStatus.EXPIRED
            raise WorkspaceConflict("lifecycle_conflict", "invite is no longer pending")
        if device.status == DeviceStatus.REVOKED:
            raise WorkspaceConflict("device_not_active", "candidate device is revoked")
        if device.status not in {DeviceStatus.PENDING, DeviceStatus.ACTIVE}:
            raise WorkspaceConflict("device_not_active", "candidate device is not active")

        existing_user_membership = self.session.scalar(
            select(WorkspaceMembership).where(
                WorkspaceMembership.user_id == user_id,
                WorkspaceMembership.status == MembershipStatus.ACTIVE,
            )
        )
        if existing_user_membership is not None:
            raise WorkspaceConflict("workspace_limit_reached", "user already belongs to a workspace")
        active_members = self.session.scalars(
            select(WorkspaceMembership).where(
                WorkspaceMembership.workspace_id == workspace.id,
                WorkspaceMembership.status == MembershipStatus.ACTIVE,
            )
        ).all()
        if len(active_members) >= 2:
            raise WorkspaceConflict("workspace_limit_reached", "workspace already has two members")

        membership = self.session.scalar(
            select(WorkspaceMembership)
            .where(
                WorkspaceMembership.workspace_id == workspace.id,
                WorkspaceMembership.user_id == user_id,
            )
            .with_for_update()
        )
        if membership is None:
            membership = WorkspaceMembership(
                workspace_id=workspace.id,
                user_id=user_id,
                member_slot=2,
                status=MembershipStatus.ACTIVE,
                joined_at=now,
            )
            self.session.add(membership)
        else:
            if membership.member_slot != 2:
                raise WorkspaceConflict("workspace_limit_reached", "workspace slot is unavailable")
            membership.status = MembershipStatus.ACTIVE
            membership.joined_at = now

        if device.status == DeviceStatus.PENDING:
            safety_code = f"{secrets.randbelow(1_000_000):06d}"
            self.session.add(
                DeviceAuthorizationRequest(
                    workspace_id=workspace.id,
                    candidate_device_id=device.id,
                    status=ApprovalStatus.PENDING,
                    safety_code_digest=hashlib.sha256(safety_code.encode("ascii")).hexdigest(),
                    expires_at=now + timedelta(seconds=self.approval_ttl_seconds),
                )
            )
        invite.status = InviteStatus.ACCEPTED
        invite.accepted_at = now
        self.session.flush()

        payload = self._state_for_user(user_id, device.id)
        self._save_idempotency(
            workspace_id=workspace.id,
            actor_user_id=user_id,
            request_id=request_id,
            route=route,
            fingerprint=fingerprint,
            status_code=200,
            payload=payload,
            expires_at=invite.expires_at,
        )
        return payload

    def _state_for_user(self, user_id: UUID, device_id: UUID) -> BootstrapPayload:
        user = self.session.get(User, user_id)
        device = self.session.get(AndroidDevice, device_id)
        if user is None or device is None or device.user_id != user_id:
            raise WorkspaceConflict("authentication_required", "authentication required")
        if device.status == DeviceStatus.REVOKED:
            raise WorkspaceConflict("device_not_active", "device is not active")

        device_payload = BootstrapDevice(
            status=public_device_status(device.status),
            can_write=device.status == DeviceStatus.ACTIVE,
        )
        membership = self.session.scalar(
            select(WorkspaceMembership).where(
                WorkspaceMembership.user_id == user_id,
                WorkspaceMembership.status == MembershipStatus.ACTIVE,
            )
        )
        if membership is not None:
            workspace = self.session.get(Workspace, membership.workspace_id)
            if workspace is None:
                raise WorkspaceConflict("not_found", "workspace not found")
            workspace_payload = self._workspace_payload(workspace, user_id)
            invite = self.session.scalar(
                select(WorkspaceInvite).where(
                    WorkspaceInvite.workspace_id == workspace.id,
                    WorkspaceInvite.status == InviteStatus.PENDING,
                    WorkspaceInvite.expires_at > self.now(),
                )
            )
            if workspace_payload.member_count >= 2:
                return BootstrapPayload(
                    state=BootstrapState.READY,
                    workspace=workspace_payload,
                    invite=None,
                    device=device_payload,
                )
            return BootstrapPayload(
                state=BootstrapState.WAITING_FOR_PARTNER,
                workspace=workspace_payload,
                invite=self._invite_payload(invite) if invite is not None else None,
                device=device_payload,
            )

        invite = self.session.scalar(
            select(WorkspaceInvite)
            .where(
                WorkspaceInvite.invited_phone == user.phone,
                WorkspaceInvite.status == InviteStatus.PENDING,
                WorkspaceInvite.expires_at > self.now(),
            )
            .order_by(WorkspaceInvite.created_at.desc(), WorkspaceInvite.id.desc())
        )
        if invite is not None:
            workspace = self.session.get(Workspace, invite.workspace_id)
            if workspace is not None:
                return BootstrapPayload(
                    state=BootstrapState.INVITED,
                    workspace=self._workspace_payload(workspace, user_id),
                    invite=self._invite_payload(invite),
                    device=device_payload,
                )
        return BootstrapPayload(
            state=BootstrapState.NEEDS_PARTNER,
            workspace=None,
            invite=None,
            device=device_payload,
        )

    def _current_device_id(self, user_id: UUID) -> UUID:
        device = self.session.scalar(
            select(AndroidDevice)
            .where(AndroidDevice.user_id == user_id, AndroidDevice.status != DeviceStatus.REVOKED)
            .order_by(AndroidDevice.created_at.asc(), AndroidDevice.id.asc())
        )
        if device is None:
            raise WorkspaceConflict("device_not_active", "active device is required")
        return device.id

    def _workspace_payload(self, workspace: Workspace, viewer_user_id: UUID) -> BootstrapWorkspace:
        rows = self.session.execute(
            select(WorkspaceMembership, User)
            .join(User, User.id == WorkspaceMembership.user_id)
            .where(
                WorkspaceMembership.workspace_id == workspace.id,
                WorkspaceMembership.status == MembershipStatus.ACTIVE,
            )
            .order_by(WorkspaceMembership.member_slot.asc(), WorkspaceMembership.id.asc())
        ).all()
        members = [
            {
                "user_id": membership.user_id,
                "display_name": public_display_name(user),
                "phone_masked": _mask_phone(user.phone),
                "member_slot": membership.member_slot,
                "membership_status": membership.status,
                "is_current": membership.user_id == viewer_user_id,
            }
            for membership, user in rows
        ]
        member_count = len(members)
        match_status = match_status_for_member_count(member_count)
        return BootstrapWorkspace(
            id=workspace.id,
            name=workspace.name,
            member_count=member_count,
            match_status=match_status,
            members=members,
        )

    def _invite_payload(self, invite: WorkspaceInvite | None) -> BootstrapInvite | None:
        if invite is None:
            return None
        return BootstrapInvite(
            id=invite.id,
            phone_masked=_mask_phone(invite.invited_phone),
            status=invite.status,
            expires_at=invite.expires_at,
        )

    def _save_idempotency(
        self,
        *,
        workspace_id: UUID,
        actor_user_id: UUID,
        request_id: UUID,
        route: str,
        fingerprint: str,
        status_code: int,
        payload: BootstrapPayload,
        expires_at: datetime,
    ) -> None:
        self.session.add(
            IdempotencyRecord(
                workspace_id=workspace_id,
                actor_user_id=actor_user_id,
                request_id=request_id,
                route=route,
                request_fingerprint=fingerprint,
                response_status=status_code,
                response_body=payload.model_dump_json(),
                expires_at=expires_at,
            )
        )
        self.session.flush()

    def _replay(self, record: IdempotencyRecord, fingerprint: str) -> BootstrapPayload:
        if record.request_fingerprint != fingerprint:
            raise WorkspaceConflict("idempotency_key_reused", "request id was used with a different payload")
        try:
            return BootstrapPayload.model_validate(json.loads(record.response_body))
        except (TypeError, ValueError) as error:
            raise WorkspaceConflict("lifecycle_conflict", "saved bootstrap response is invalid") from error


def _normalize_phone(phone: str) -> str:
    try:
        return normalize_auth_phone(phone)
    except SmsAuthError as error:
        raise WorkspaceConflict(error.code, error.message) from error


def _mask_phone(phone: str) -> str:
    if len(phone) <= 5:
        return phone
    prefix_length = 3 if phone.startswith("+86") else 2
    prefix = phone[:prefix_length]
    mask_length = 6 if phone.startswith("+86") else max(4, len(phone) - prefix_length - 4)
    return f"{prefix}{'*' * mask_length}{phone[-4:]}"


__all__ = ["WorkspaceBootstrapService"]
