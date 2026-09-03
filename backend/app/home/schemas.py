from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field


class HomeTaskSection(BaseModel):
    """A bounded list and its independent truncation marker."""

    items: list[dict[str, Any]] = Field(default_factory=list)
    has_more: bool = False


class HomeResponse(BaseModel):
    """Server-authoritative action lists for the signed-in workspace member."""

    current_tasks: HomeTaskSection = Field(default_factory=HomeTaskSection)
    blocked_tasks: HomeTaskSection = Field(default_factory=HomeTaskSection)
    review_tasks: HomeTaskSection = Field(default_factory=HomeTaskSection)
    pending_approval_count: int = Field(ge=0)
