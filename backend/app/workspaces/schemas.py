from __future__ import annotations

from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class CreateWorkspaceBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: str | None = Field(default=None, max_length=160)


class WorkspaceInviteBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    phone: str = Field(min_length=1, max_length=40)


class BindPartnerBody(BaseModel):
    model_config = ConfigDict(extra="forbid")

    phone: str = Field(min_length=1, max_length=40)
    request_id: UUID


class AcceptInviteBody(BaseModel):
    model_config = ConfigDict(extra="forbid")

    device_id: UUID | None = None
    request_id: UUID
