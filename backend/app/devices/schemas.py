from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field


class DeviceAuthorizationRequestBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    public_key: str = Field(min_length=1, max_length=4096)
    label: str | None = Field(default=None, max_length=120)


class DeviceSignatureBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    signature: str = Field(min_length=1, max_length=4096)
