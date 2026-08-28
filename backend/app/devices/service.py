"""Device-domain operations exposed to the Android client."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Callable
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.enums import DeviceStatus
from app.db.models import AndroidDevice
from app.recovery.service import RecoveryConflict, RecoveryService
from app.workspaces.bootstrap_schemas import DeviceSummary, public_device_status
from app.workspaces.service import ApprovalChallenge, WorkspaceConflict, WorkspaceService


class DeviceConflict(Exception):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


class DeviceService:
    """List and revoke durable Android devices without exposing key material."""

    def __init__(
        self,
        session: Session,
        *,
        now: Callable[[], datetime] = lambda: datetime.now(timezone.utc),
    ) -> None:
        self.session = session
        self.now = now

    def list_for_user(self, user_id: UUID, current_device_id: UUID | None) -> list[DeviceSummary]:
        devices = self.session.scalars(
            select(AndroidDevice)
            .where(AndroidDevice.user_id == user_id)
            .order_by(AndroidDevice.created_at.asc(), AndroidDevice.id.asc())
        ).all()
        return [
            DeviceSummary(
                id=device.id,
                platform=device.platform,
                label=device.label,
                status=public_device_status(device.status),
                is_current=device.id == current_device_id,
                can_write=device.status == DeviceStatus.ACTIVE,
                created_at=device.created_at,
                enrolled_at=device.enrolled_at,
                revoked_at=device.revoked_at,
            )
            for device in devices
        ]

    def revoke(self, device_id: UUID, actor_user_id: UUID, actor_device_id: UUID) -> DeviceSummary:
        try:
            device = RecoveryService(self.session, now=self.now).revoke_device(
                device_id,
                actor_user_id,
                actor_device_id,
            )
        except RecoveryConflict as error:
            raise DeviceConflict(error.code, str(error)) from error
        return DeviceSummary(
            id=device.id,
            platform=device.platform,
            label=device.label,
            status=public_device_status(device.status),
            is_current=device.id == actor_device_id,
            can_write=device.status == DeviceStatus.ACTIVE,
            created_at=device.created_at,
            enrolled_at=device.enrolled_at,
            revoked_at=device.revoked_at,
        )


__all__ = [
    "ApprovalChallenge",
    "DeviceConflict",
    "DeviceService",
    "DeviceSummary",
    "WorkspaceConflict",
    "WorkspaceService",
]
