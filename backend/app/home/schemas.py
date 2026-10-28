from __future__ import annotations

from datetime import datetime
from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel, Field


HomeEntryName = Literal["needs_me", "waiting_on_other", "due_this_week", "due_soon"]


class HomeTaskSection(BaseModel):
    """A task list and its independent truncation marker."""

    items: list[dict[str, Any]] = Field(default_factory=list)
    has_more: bool = False


class HomeApprovalItem(BaseModel):
    """A pending request together with its current task snapshot."""

    approval_request: dict[str, Any]
    task: dict[str, Any] | None = None


class HomeApprovalSection(BaseModel):
    """A bounded pending-request entry list."""

    items: list[HomeApprovalItem] = Field(default_factory=list)
    has_more: bool = False


class HomeWeek(BaseModel):
    """Business-calendar week boundaries serialized as UTC instants."""

    timezone: str
    start: datetime
    end: datetime


class HomeEntryCounts(BaseModel):
    """Independent counts for the three home entry questions."""

    needs_me: int = Field(ge=0)
    waiting_on_other: int = Field(ge=0)
    due_this_week: int = Field(ge=0)
    due_soon: int = Field(ge=0)


class HomeEntries(BaseModel):
    """Prefetched data for each canonical home entry."""

    needs_me: HomeApprovalSection = Field(default_factory=HomeApprovalSection)
    waiting_on_other: HomeApprovalSection = Field(default_factory=HomeApprovalSection)
    due_this_week: HomeTaskSection = Field(default_factory=HomeTaskSection)
    due_soon: HomeTaskSection = Field(default_factory=HomeTaskSection)


class HomeEntriesPage(BaseModel):
    """A page for one canonical home entry."""

    count: int = Field(ge=0)
    items: list[dict[str, Any]] = Field(default_factory=list)
    has_more: bool = False
    next_cursor: str | None = None


class MomentProjection(BaseModel):
    """The deduplicated three-section projection for the default workbench."""

    # Canonical names. Keep the *_tasks names below for the existing Android
    # and Web consumers until they migrate.
    blocked: HomeTaskSection = Field(default_factory=HomeTaskSection)
    mine: HomeTaskSection = Field(default_factory=HomeTaskSection)
    other: HomeTaskSection = Field(default_factory=HomeTaskSection)
    blocked_tasks: HomeTaskSection = Field(default_factory=HomeTaskSection)
    my_tasks: HomeTaskSection = Field(default_factory=HomeTaskSection)
    other_tasks: HomeTaskSection = Field(default_factory=HomeTaskSection)
    all_tasks_has_more: bool = False


class HomeResponse(BaseModel):
    """Compatibility action lists plus the server-authoritative moment view."""

    viewer_user_id: UUID | None = None
    as_of: datetime | None = None
    week: HomeWeek | None = None
    entry_counts: HomeEntryCounts | None = None
    current_tasks: HomeTaskSection = Field(default_factory=HomeTaskSection)
    blocked_tasks: HomeTaskSection = Field(default_factory=HomeTaskSection)
    review_tasks: HomeTaskSection = Field(default_factory=HomeTaskSection)
    pending_approval_count: int = Field(ge=0)
    moment: MomentProjection = Field(default_factory=MomentProjection)
    needs_action_count: int = Field(default=0, ge=0)
    waiting_on_other_count: int = Field(default=0, ge=0)
    week_due_count: int = Field(default=0, ge=0)
    due_soon_count: int = Field(default=0, ge=0)
    entries: HomeEntries = Field(default_factory=HomeEntries)


# Resource-oriented aliases keep imports stable for callers that use the
# terminology from the API contract.
HomeEntryProjection = HomeEntries
HomeEntryCount = HomeEntryCounts
MomentSection = HomeTaskSection
