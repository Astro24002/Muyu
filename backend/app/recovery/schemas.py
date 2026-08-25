from __future__ import annotations

from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class DeviceRecoveryBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    workspace_id: UUID


class PhoneChangeBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    new_phone: str = Field(min_length=1, max_length=40)
