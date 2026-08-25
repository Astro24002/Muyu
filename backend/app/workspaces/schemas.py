from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field


class CreateWorkspaceBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: str | None = Field(default=None, max_length=160)


class WorkspaceInviteBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    phone: str = Field(min_length=1, max_length=40)
