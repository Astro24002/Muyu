from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field


class Problem(BaseModel):
    type: str
    title: str
    status: int
    detail: str | None = None
    code: str
    request_id: str | None = None
    errors: dict[str, Any] = Field(default_factory=dict)
