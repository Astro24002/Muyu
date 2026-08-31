from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class DeviceAuthorizationRequestBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    public_key: str = Field(min_length=1, max_length=4096)
    label: str | None = Field(default=None, max_length=120)


class DeviceSignatureBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    signature: str = Field(min_length=1, max_length=4096)


class DeviceAuthorizationRequestSummary(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID
    candidate_device_id: UUID
    candidate_device_label: str | None = None
    candidate_platform: str
    candidate_user_id: UUID
    candidate_phone_masked: str
    requester_user_id: UUID
    requester_phone_masked: str
    is_incoming: bool
    status: str
    created_at: datetime
    expires_at: datetime
