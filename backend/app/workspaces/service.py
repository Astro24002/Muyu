from __future__ import annotations

import hashlib
import hmac
import secrets
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Callable
from uuid import UUID

import phonenumbers
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.enums import ApprovalStatus, ChallengeStatus, DeviceStatus, InviteStatus, MembershipStatus
from app.db.models import (
    AndroidDevice,
    DeviceAuthorizationChallenge,
    DeviceAuthorizationRequest,
    User,
    Workspace,
    WorkspaceCursor,
    WorkspaceInvite,
    WorkspaceMembership,
)
from app.devices.signatures import verify_device_signature, signed_action_payload
from app.workspaces.classifications import ensure_default_classification


class WorkspaceConflict(Exception):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


@dataclass(frozen=True)
class ApprovalChallenge:
    request_id: UUID
    nonce: bytes
    expires_at: datetime


class WorkspaceService:
    def __init__(
        self,
        session: Session,
        *,
        now: Callable[[], datetime] = lambda: datetime.now(timezone.utc),
        approval_ttl_seconds: int = 600,
        approval_secret: str = "local-development-approval-secret",
    ) -> None:
        self.session = session
        self.now = now
        self.approval_ttl_seconds = min(900, max(60, approval_ttl_seconds))
        self.approval_secret = approval_secret.encode("utf-8")

    def create_workspace(self, owner_user_id: UUID, *, name: str | None = None) -> Workspace:
        owner = self.session.scalar(select(User).where(User.id == owner_user_id).with_for_update())
        if owner is None:
            raise WorkspaceConflict("authentication_required", "user does not exist")
        existing = self.session.scalar(
            select(WorkspaceMembership).where(
                WorkspaceMembership.user_id == owner_user_id,
                WorkspaceMembership.status == MembershipStatus.ACTIVE,
            )
        )
        if existing is not None:
            raise WorkspaceConflict("workspace_limit_reached", "user already belongs to a workspace")
        workspace = Workspace(name=name)
        self.session.add(workspace)
        self.session.flush()
        self.session.add(
            WorkspaceMembership(
                workspace_id=workspace.id,
                user_id=owner_user_id,
                member_slot=1,
                status=MembershipStatus.ACTIVE,
                joined_at=self.now(),
            )
        )
        self.session.add(WorkspaceCursor(workspace_id=workspace.id, next_cursor=1))
        self.session.flush()
        ensure_default_classification(self.session, workspace.id, owner_user_id)
        return workspace

    def create_invite(self, workspace_id: UUID, inviter_user_id: UUID, invited_phone: str) -> WorkspaceInvite:
        self._require_active_member(workspace_id, inviter_user_id)
        self.session.scalar(select(Workspace).where(Workspace.id == workspace_id).with_for_update())
        normalized = normalize_phone(invited_phone)
        if self.session.scalar(
            select(WorkspaceMembership).where(
                WorkspaceMembership.workspace_id == workspace_id,
                WorkspaceMembership.status == MembershipStatus.ACTIVE,
                WorkspaceMembership.member_slot == 2,
            )
        ):
            raise WorkspaceConflict("workspace_limit_reached", "workspace already has two members")
        invite = WorkspaceInvite(
            workspace_id=workspace_id,
            inviter_user_id=inviter_user_id,
            invited_phone=normalized,
            status=InviteStatus.PENDING,
            expires_at=self.now() + timedelta(days=7),
        )
        self.session.add(invite)
        self.session.flush()
        return invite

    def accept_invite(self, invite_id: UUID, user_id: UUID, candidate_device_id: UUID) -> tuple[DeviceAuthorizationRequest, str]:
        invite = self.session.scalar(select(WorkspaceInvite).where(WorkspaceInvite.id == invite_id).with_for_update())
        user = self.session.get(User, user_id)
        device = self.session.get(AndroidDevice, candidate_device_id)
        if invite is None or user is None or device is None:
            raise WorkspaceConflict("not_found", "invite or candidate device not found")
        if invite.status != InviteStatus.PENDING or invite.expires_at <= self.now():
            raise WorkspaceConflict("lifecycle_conflict", "invite is no longer pending")
        self.session.scalar(select(Workspace).where(Workspace.id == invite.workspace_id).with_for_update())
        if normalize_phone(user.phone) != invite.invited_phone or device.user_id != user_id:
            raise WorkspaceConflict("approval_not_allowed", "invite does not match this user")
        if device.status not in {DeviceStatus.PENDING, DeviceStatus.ACTIVE}:
            raise WorkspaceConflict("device_not_active", "candidate device is not pending")
        active_members = self.session.scalars(
            select(WorkspaceMembership).where(
                WorkspaceMembership.workspace_id == invite.workspace_id,
                WorkspaceMembership.status == MembershipStatus.ACTIVE,
            )
        ).all()
        if len(active_members) >= 2:
            raise WorkspaceConflict("workspace_limit_reached", "workspace already has two members")
        membership = self.session.scalar(
            select(WorkspaceMembership).where(
                WorkspaceMembership.workspace_id == invite.workspace_id,
                WorkspaceMembership.user_id == user_id,
            )
        )
        if membership is None:
            self.session.add(
                WorkspaceMembership(
                    workspace_id=invite.workspace_id,
                    user_id=user_id,
                    member_slot=2,
                    status=MembershipStatus.PENDING,
                )
            )
        safety_code = f"{secrets.randbelow(1_000_000):06d}"
        request = DeviceAuthorizationRequest(
            workspace_id=invite.workspace_id,
            candidate_device_id=candidate_device_id,
            status=ApprovalStatus.PENDING,
            safety_code_digest=self._digest(safety_code),
            expires_at=self.now() + timedelta(seconds=self.approval_ttl_seconds),
        )
        self.session.add(request)
        invite.status = InviteStatus.ACCEPTED
        invite.accepted_at = self.now()
        self.session.flush()
        return request, safety_code

    def begin_approval(self, request_id: UUID, approving_device_id: UUID) -> ApprovalChallenge:
        request = self._pending_request(request_id)
        approving = self.session.get(AndroidDevice, approving_device_id)
        if approving is None or approving.status != DeviceStatus.ACTIVE:
            raise WorkspaceConflict("approval_not_allowed", "approving device is not active")
        if approving.user_id == self.session.scalar(
            select(AndroidDevice.user_id).where(AndroidDevice.id == request.candidate_device_id)
        ):
            raise WorkspaceConflict("approval_not_allowed", "self approval is not allowed")
        if not self._is_workspace_member(request.workspace_id, approving.user_id):
            raise WorkspaceConflict("workspace_access_denied", "approving device is outside the workspace")
        nonce = secrets.token_bytes(32)
        expires_at = min(request.expires_at, self.now() + timedelta(seconds=self.approval_ttl_seconds))
        challenge = DeviceAuthorizationChallenge(
            request_id=request.id,
            nonce=nonce,
            challenge_digest=hashlib.sha256(nonce).hexdigest(),
            expires_at=expires_at,
            status=ChallengeStatus.PENDING,
        )
        request.approving_device_id = approving_device_id
        self.session.add(challenge)
        self.session.flush()
        return ApprovalChallenge(request_id=request.id, nonce=nonce, expires_at=expires_at)

    def approve(self, request_id: UUID, approving_device_id: UUID, signature: bytes) -> DeviceAuthorizationRequest:
        request = self._pending_request(request_id)
        if request.approving_device_id != approving_device_id:
            raise WorkspaceConflict("approval_not_allowed", "wrong approving device")
        challenge = self.session.scalar(
            select(DeviceAuthorizationChallenge)
            .where(
                DeviceAuthorizationChallenge.request_id == request_id,
                DeviceAuthorizationChallenge.status == ChallengeStatus.PENDING,
            )
            .order_by(DeviceAuthorizationChallenge.created_at.desc())
            .with_for_update()
        )
        approving = self.session.get(AndroidDevice, approving_device_id)
        candidate = self.session.get(AndroidDevice, request.candidate_device_id)
        if challenge is None or challenge.expires_at <= self.now():
            raise WorkspaceConflict("approval_challenge_expired", "approval challenge expired")
        if approving is None or candidate is None or approving.status != DeviceStatus.ACTIVE:
            raise WorkspaceConflict("approval_not_allowed", "device is not eligible")
        payload = signed_action_payload(
            action="DEVICE_APPROVE",
            approval_id=request.id,
            actor_device_id=approving_device_id,
            workspace_id=request.workspace_id,
            nonce=challenge.nonce,
            expires_at=challenge.expires_at,
        )
        if not verify_device_signature(approving.public_key_der, payload, signature):
            raise WorkspaceConflict("invalid_device_signature", "invalid device signature")
        membership = self.session.scalar(
            select(WorkspaceMembership).where(
                WorkspaceMembership.workspace_id == request.workspace_id,
                WorkspaceMembership.user_id == candidate.user_id,
            ).with_for_update()
        )
        if membership is None:
            raise WorkspaceConflict("approval_not_allowed", "candidate membership is missing")
        membership.status = MembershipStatus.ACTIVE
        membership.joined_at = self.now()
        candidate.status = DeviceStatus.ACTIVE
        candidate.enrolled_at = self.now()
        request.status = ApprovalStatus.APPROVED
        request.approved_at = self.now()
        challenge.status = ChallengeStatus.CONSUMED
        challenge.consumed_at = self.now()
        self.session.flush()
        return request

    def reject(self, request_id: UUID, approving_device_id: UUID) -> DeviceAuthorizationRequest:
        request = self._pending_request(request_id)
        approving = self.session.get(AndroidDevice, approving_device_id)
        candidate = self.session.get(AndroidDevice, request.candidate_device_id)
        if approving is None or candidate is None or approving.status != DeviceStatus.ACTIVE:
            raise WorkspaceConflict("approval_not_allowed", "device is not eligible")
        if approving.user_id == candidate.user_id:
            raise WorkspaceConflict("approval_not_allowed", "self approval is not allowed")
        if not self._is_workspace_member(request.workspace_id, approving.user_id):
            raise WorkspaceConflict("workspace_access_denied", "approving device is outside the workspace")
        if not self._is_workspace_member(request.workspace_id, candidate.user_id):
            raise WorkspaceConflict("approval_not_allowed", "candidate is outside the workspace")
        request.status = ApprovalStatus.REJECTED
        self.session.flush()
        return request

    def _pending_request(self, request_id: UUID) -> DeviceAuthorizationRequest:
        request = self.session.scalar(
            select(DeviceAuthorizationRequest).where(DeviceAuthorizationRequest.id == request_id).with_for_update()
        )
        if request is None:
            raise WorkspaceConflict("not_found", "authorization request not found")
        if request.status != ApprovalStatus.PENDING or request.expires_at <= self.now():
            raise WorkspaceConflict("approval_challenge_expired", "authorization request expired")
        return request

    def _require_active_member(self, workspace_id: UUID, user_id: UUID) -> WorkspaceMembership:
        membership = self.session.scalar(
            select(WorkspaceMembership).where(
                WorkspaceMembership.workspace_id == workspace_id,
                WorkspaceMembership.user_id == user_id,
                WorkspaceMembership.status == MembershipStatus.ACTIVE,
            ).with_for_update()
        )
        if membership is None:
            raise WorkspaceConflict("workspace_access_denied", "active membership required")
        return membership

    def _is_workspace_member(self, workspace_id: UUID, user_id: UUID) -> bool:
        return self.session.scalar(
            select(WorkspaceMembership.id).where(
                WorkspaceMembership.workspace_id == workspace_id,
                WorkspaceMembership.user_id == user_id,
                WorkspaceMembership.status == MembershipStatus.ACTIVE,
            )
        ) is not None

    def _digest(self, value: str) -> str:
        return hmac.new(self.approval_secret, value.encode("ascii"), "sha256").hexdigest()


def normalize_phone(phone: str) -> str:
    try:
        parsed = phonenumbers.parse(phone, None)
    except phonenumbers.NumberParseException as error:
        raise WorkspaceConflict("invalid_request", "phone must be E.164") from error
    if not phone.strip().startswith("+") or not phonenumbers.is_valid_number(parsed):
        raise WorkspaceConflict("invalid_request", "phone must be E.164")
    return phonenumbers.format_number(parsed, phonenumbers.PhoneNumberFormat.E164)
