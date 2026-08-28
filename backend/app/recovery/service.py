from __future__ import annotations

import secrets
from datetime import datetime, timedelta, timezone
from typing import Callable
from uuid import UUID

from sqlalchemy import select, update
from sqlalchemy.orm import Session

from app.db.enums import ApprovalStatus, DeviceStatus, MembershipStatus, WebSessionStatus
from app.db.models import (
    ActivityEvent,
    AndroidDevice,
    DeviceAuthorizationRequest,
    MobileSession,
    PhoneChangeRequest,
    RecoveryRequest,
    User,
    WebSession,
    WorkspaceMembership,
)


class RecoveryConflict(Exception):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


class RecoveryService:
    def __init__(
        self,
        session: Session,
        *,
        now: Callable[[], datetime] = lambda: datetime.now(timezone.utc),
        ttl_seconds: int = 600,
    ) -> None:
        self.session = session
        self.now = now
        self.ttl_seconds = min(900, max(60, ttl_seconds))

    def start_device_loss(
        self,
        workspace_id: UUID,
        requester_user_id: UUID,
        requester_device_id: UUID | None = None,
    ) -> RecoveryRequest:
        self._member(workspace_id, requester_user_id)
        if requester_device_id is not None:
            requester_device = self.session.get(AndroidDevice, requester_device_id)
            if (
                requester_device is None
                or requester_device.user_id != requester_user_id
                or requester_device.status == DeviceStatus.REVOKED
            ):
                raise RecoveryConflict("device_not_active", "requesting device is not eligible")
        request = RecoveryRequest(
            workspace_id=workspace_id,
            requester_user_id=requester_user_id,
            requester_device_id=requester_device_id,
            status=ApprovalStatus.PENDING,
            expires_at=self.now() + timedelta(seconds=self.ttl_seconds),
        )
        self.session.add(request)
        self.session.flush()
        self._audit(workspace_id, requester_user_id, "device_loss_requested", request.id)
        return request

    def approve_device_loss(
        self,
        request_id: UUID,
        approver_user_id: UUID,
        approver_device_id: UUID | None = None,
    ) -> RecoveryRequest:
        request = self._pending(request_id)
        if request.requester_user_id == approver_user_id:
            raise RecoveryConflict("approval_not_allowed", "recovery requires the other member")
        self._member(request.workspace_id, approver_user_id)
        if approver_device_id is not None:
            approver_device = self.session.get(AndroidDevice, approver_device_id)
            if (
                approver_device is None
                or approver_device.user_id != approver_user_id
                or approver_device.status == DeviceStatus.REVOKED
            ):
                raise RecoveryConflict("device_not_active", "approving device is not eligible")
        request.approver_user_id = approver_user_id
        request.approver_device_id = approver_device_id
        request.status = ApprovalStatus.APPROVED
        request.approved_at = self.now()
        self._revoke_workspace_credentials(request.workspace_id)
        # Rotate all workspace credentials, then activate exactly the devices
        # that participated in the recovery request. Both participants must
        # authenticate again after this rotation.
        for device_id in (request.requester_device_id, request.approver_device_id):
            if device_id is None:
                continue
            device = self.session.get(AndroidDevice, device_id)
            if device is not None:
                device.status = DeviceStatus.ACTIVE
                device.revoked_at = None
                device.enrolled_at = self.now()
        self._audit(request.workspace_id, approver_user_id, "device_loss_approved", request.id)
        return request

    def revoke_device(self, device_id: UUID, actor_user_id: UUID, actor_device_id: UUID | None = None) -> AndroidDevice:
        device = self.session.scalar(select(AndroidDevice).where(AndroidDevice.id == device_id).with_for_update())
        if device is None:
            raise RecoveryConflict("not_found", "device not found")
        if device.user_id != actor_user_id:
            raise RecoveryConflict("approval_not_allowed", "only your other devices can be revoked")
        if actor_device_id == device_id:
            raise RecoveryConflict("approval_not_allowed", "cannot revoke the current device")
        if actor_device_id is not None:
            actor_device = self.session.get(AndroidDevice, actor_device_id)
            if actor_device is None or actor_device.user_id != actor_user_id:
                raise RecoveryConflict("approval_not_allowed", "actor device is not owned by the actor")
            if actor_device.status == DeviceStatus.REVOKED:
                raise RecoveryConflict("device_not_active", "actor device is not active")
            if actor_device.status != DeviceStatus.ACTIVE:
                raise RecoveryConflict("device_not_verified", "actor device has not been verified")
        if device.status == DeviceStatus.REVOKED:
            raise RecoveryConflict("device_already_revoked", "device is already revoked")
        revoked_at = self.now()
        device.status = DeviceStatus.REVOKED
        device.revoked_at = revoked_at
        device.updated_at = revoked_at
        self.session.execute(
            update(MobileSession)
            .where(MobileSession.device_id == device_id, MobileSession.revoked_at.is_(None))
            .values(revoked_at=revoked_at, updated_at=revoked_at)
        )
        self.session.execute(
            update(DeviceAuthorizationRequest)
            .where(
                DeviceAuthorizationRequest.candidate_device_id == device_id,
                DeviceAuthorizationRequest.status == ApprovalStatus.PENDING,
            )
            .values(
                status=ApprovalStatus.REVOKED,
                revoked_at=revoked_at,
                updated_at=revoked_at,
            )
        )
        self.session.execute(
            update(WebSession)
            .where(WebSession.approving_device_id == device_id, WebSession.status == WebSessionStatus.ACTIVE)
            .values(status=WebSessionStatus.REVOKED, revoked_at=revoked_at, updated_at=revoked_at)
        )
        self._audit(None, actor_user_id, "device_revoked", device_id)
        return device

    def start_phone_change(self, user_id: UUID, new_phone: str) -> PhoneChangeRequest:
        user = self.session.get(User, user_id)
        if user is None:
            raise RecoveryConflict("not_found", "user not found")
        from app.workspaces.service import normalize_phone

        normalized_phone = normalize_phone(new_phone)
        duplicate = self.session.scalar(select(User.id).where(User.phone == normalized_phone, User.id != user_id))
        if duplicate is not None:
            raise RecoveryConflict("lifecycle_conflict", "phone number is already registered")
        request = PhoneChangeRequest(
            user_id=user_id,
            workspace_id=self._workspace_for(user_id),
            old_phone=user.phone,
            new_phone=normalized_phone,
            status=ApprovalStatus.PENDING,
            expires_at=self.now() + timedelta(seconds=self.ttl_seconds),
        )
        self.session.add(request)
        self.session.flush()
        return request

    def approve_phone_change(self, request_id: UUID, approver_user_id: UUID) -> PhoneChangeRequest:
        request = self.session.scalar(select(PhoneChangeRequest).where(PhoneChangeRequest.id == request_id).with_for_update())
        if request is None or request.status != ApprovalStatus.PENDING or request.expires_at <= self.now():
            raise RecoveryConflict("lifecycle_conflict", "phone change is no longer pending")
        if request.user_id == approver_user_id:
            raise RecoveryConflict("approval_not_allowed", "phone change requires the other member")
        if request.workspace_id is not None:
            self._member(request.workspace_id, approver_user_id)
        user = self.session.get(User, request.user_id)
        if user is None:
            raise RecoveryConflict("not_found", "user not found")
        user.phone = request.new_phone
        request.approver_user_id = approver_user_id
        request.status = ApprovalStatus.APPROVED
        request.completed_at = self.now()
        self._audit(request.workspace_id, approver_user_id, "phone_change_completed", request.id)
        return request

    def _pending(self, request_id: UUID) -> RecoveryRequest:
        request = self.session.scalar(select(RecoveryRequest).where(RecoveryRequest.id == request_id).with_for_update())
        if request is None or request.status != ApprovalStatus.PENDING or request.expires_at <= self.now():
            raise RecoveryConflict("lifecycle_conflict", "recovery is no longer pending")
        return request

    def _member(self, workspace_id: UUID, user_id: UUID) -> WorkspaceMembership:
        member = self.session.scalar(
            select(WorkspaceMembership).where(
                WorkspaceMembership.workspace_id == workspace_id,
                WorkspaceMembership.user_id == user_id,
                WorkspaceMembership.status == MembershipStatus.ACTIVE,
            ).with_for_update()
        )
        if member is None:
            raise RecoveryConflict("workspace_access_denied", "active membership required")
        return member

    def _workspace_for(self, user_id: UUID) -> UUID | None:
        return self.session.scalar(
            select(WorkspaceMembership.workspace_id).where(
                WorkspaceMembership.user_id == user_id,
                WorkspaceMembership.status == MembershipStatus.ACTIVE,
            )
        )

    def _revoke_workspace_credentials(self, workspace_id: UUID) -> None:
        user_ids = select(WorkspaceMembership.user_id).where(
            WorkspaceMembership.workspace_id == workspace_id,
            WorkspaceMembership.status == MembershipStatus.ACTIVE,
        )
        device_ids = select(AndroidDevice.id).where(AndroidDevice.user_id.in_(user_ids))
        self.session.execute(
            update(AndroidDevice).where(AndroidDevice.id.in_(device_ids)).values(status=DeviceStatus.REVOKED, revoked_at=self.now(), updated_at=self.now())
        )
        self.session.execute(update(MobileSession).where(MobileSession.device_id.in_(device_ids)).values(revoked_at=self.now(), updated_at=self.now()))
        self.session.execute(update(WebSession).where(WebSession.workspace_id == workspace_id).values(status=WebSessionStatus.REVOKED, revoked_at=self.now(), updated_at=self.now()))

    def _audit(self, workspace_id: UUID | None, actor_user_id: UUID, action: str, subject_id: UUID) -> None:
        if workspace_id is None:
            workspace_id = self._workspace_for(actor_user_id)
        if workspace_id is None:
            return
        self.session.add(
            ActivityEvent(
                workspace_id=workspace_id,
                actor_user_id=actor_user_id,
                event_type=action,
                payload={"subject_id": str(subject_id)},
            )
        )
