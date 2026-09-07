from __future__ import annotations

from typing import Literal
from uuid import UUID

from app.db.enums import PublicDeviceStatus

from pydantic import BaseModel, ConfigDict, Field


class SmsSendRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    phone: str = Field(min_length=1, max_length=40)


class DeviceMetadata(BaseModel):
    model_config = ConfigDict(extra="forbid")

    public_key_der: str = Field(min_length=1, max_length=4096)
    label: str | None = Field(default=None, max_length=120)


class SmsVerifyRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    phone: str = Field(min_length=1, max_length=40)
    code: str = Field(min_length=1, max_length=32)
    device: DeviceMetadata


class MobileRefreshRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    refresh_token: str = Field(min_length=1, max_length=512)


class ProfileUpdateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    display_name: str | None = Field(max_length=120)


class MobileUserResponse(BaseModel):
    id: UUID
    phone: str
    display_name: str | None = None
    workspace_id: UUID | None = None
    device_id: UUID
    device_status: PublicDeviceStatus | None = None
    can_write: bool = False


class MobileAuthResponse(BaseModel):
    user: MobileUserResponse
    device_id: UUID
    access_token: str
    refresh_token: str
    token_type: Literal["bearer"] = "bearer"
    device_status: PublicDeviceStatus
    can_write: bool
