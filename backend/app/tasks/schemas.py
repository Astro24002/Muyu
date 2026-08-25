from __future__ import annotations

from typing import Any
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator


class CreateTaskRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    request_id: UUID
    title: str = Field(min_length=1, max_length=200)
    description: str = Field(default="", max_length=10000)
    due_at: str | None = None


class PatchTaskRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    request_id: UUID
    changes: dict[str, Any]
    base_field_versions: dict[str, int]

    @model_validator(mode="after")
    def versions_match_changed_fields(self) -> "PatchTaskRequest":
        if set(self.changes) != set(self.base_field_versions):
            raise ValueError("base versions must match changed fields")
        return self


class LifecycleRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    request_id: UUID
    action: str
    base_lifecycle_version: int


class ResolveConflictRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    request_id: UUID
    resolution: str


class CommentRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    request_id: UUID
    body: str = Field(min_length=1, max_length=10000)


class DelayRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    request_id: UUID
    new_due_at: str
    reason: str = Field(min_length=1, max_length=50)
    note: str | None = Field(default=None, max_length=2000)

