from __future__ import annotations

from datetime import datetime
from typing import Literal, Mapping
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

from app.db.enums import BootstrapState, DeviceStatus, InviteStatus, MembershipStatus, PublicDeviceStatus


PUBLIC_DEVICE_STATUS: Mapping[DeviceStatus, PublicDeviceStatus] = {
    DeviceStatus.PENDING: PublicDeviceStatus.UNVERIFIED,
    DeviceStatus.ACTIVE: PublicDeviceStatus.VERIFIED,
    DeviceStatus.REVOKED: PublicDeviceStatus.REVOKED,
}

# Keep a descriptive alias for callers that prefer an explicit map suffix.
PUBLIC_DEVICE_STATUS_MAP = PUBLIC_DEVICE_STATUS


def public_device_status(status: DeviceStatus | str) -> PublicDeviceStatus:
    """Translate persisted device state to the public API vocabulary."""

    persisted = status if isinstance(status, DeviceStatus) else DeviceStatus(status)
    return PUBLIC_DEVICE_STATUS[persisted]


to_public_device_status = public_device_status


def device_status_for_device_count(existing_device_count: int) -> DeviceStatus:
    """Return the enrollment state for a device being added to an account."""

    if existing_device_count < 0:
        raise ValueError("existing device count cannot be negative")
    return DeviceStatus.ACTIVE if existing_device_count == 0 else DeviceStatus.PENDING


class BootstrapDevice(BaseModel):
    model_config = ConfigDict(extra="forbid")

    status: PublicDeviceStatus
    can_write: bool


class BootstrapWorkspace(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID
    name: str | None = None
    member_count: int = Field(ge=0)
    match_status: Literal["waiting_partner", "matched", "error"] = "waiting_partner"
    members: list["BootstrapMember"] = Field(default_factory=list)


class BootstrapMember(BaseModel):
    model_config = ConfigDict(extra="forbid")

    user_id: UUID
    display_name: str | None = None
    phone_masked: str
    member_slot: int = Field(ge=1, le=2)
    membership_status: MembershipStatus
    is_current: bool = False


class BootstrapInvite(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID
    phone_masked: str
    status: InviteStatus
    expires_at: datetime


class BootstrapPayload(BaseModel):
    model_config = ConfigDict(extra="forbid")

    state: BootstrapState
    workspace: BootstrapWorkspace | None = None
    invite: BootstrapInvite | None = None
    device: BootstrapDevice


# The response name is useful at the HTTP boundary while the service contract
# uses ``BootstrapPayload``. They intentionally share one schema definition.
BootstrapResponse = BootstrapPayload


class DeviceSummary(BaseModel):
    """Public Android-device projection used by device-management endpoints."""

    model_config = ConfigDict(extra="forbid")

    id: UUID
    platform: str
    label: str | None = None
    status: PublicDeviceStatus
    is_current: bool
    can_write: bool = False
    created_at: datetime
    enrolled_at: datetime | None = None
    revoked_at: datetime | None = None


__all__ = [
    "BootstrapDevice",
    "BootstrapInvite",
    "BootstrapMember",
    "BootstrapPayload",
    "BootstrapResponse",
    "BootstrapState",
    "BootstrapWorkspace",
    "DeviceSummary",
    "PUBLIC_DEVICE_STATUS",
    "PUBLIC_DEVICE_STATUS_MAP",
    "PublicDeviceStatus",
    "device_status_for_device_count",
    "public_device_status",
    "to_public_device_status",
]
