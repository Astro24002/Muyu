from __future__ import annotations

from datetime import datetime
from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.db.enums import TaskApprovalRequestStatus, TaskApprovalRequestType


class ApprovalRequestCreate(BaseModel):
    """Wire contract for creating a task approval request.

    The service performs target-specific validation.  The schema keeps the
    request shape strict and catches the common field/version mismatch before
    the request reaches persistence.
    """

    model_config = ConfigDict(extra="forbid")

    request_id: UUID
    task_id: UUID
    comment_id: UUID | None = None
    request_type: TaskApprovalRequestType
    proposed_changes: dict[str, Any] = Field(default_factory=dict)
    base_field_versions: dict[str, int] = Field(default_factory=dict)

    @model_validator(mode="after")
    def versions_match_changed_fields(self) -> "ApprovalRequestCreate":
        if self.request_type in {
            TaskApprovalRequestType.TASK_UPDATE,
            TaskApprovalRequestType.QUADRANT_UPDATE,
            TaskApprovalRequestType.ASSIGNEE_UPDATE,
            TaskApprovalRequestType.HANDLER_TRANSFER,
        } and set(self.proposed_changes) != set(self.base_field_versions):
            raise ValueError("base versions must match changed fields")
        return self


class ApprovalRejectRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    request_id: UUID
    reason: str | None = Field(default=None, max_length=2000)


class ApprovalActionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    request_id: UUID


class ApprovalRequestRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    workspace_id: UUID
    task_id: UUID
    comment_id: UUID | None
    requester_id: UUID
    approver_id: UUID
    request_type: TaskApprovalRequestType
    proposed_changes: dict[str, Any]
    base_field_versions: dict[str, Any]
    request_id: UUID
    status: TaskApprovalRequestStatus
    created_at: datetime
    reviewed_at: datetime | None
    reviewed_by: UUID | None
    rejection_reason: str | None
    resolved_cursor: int | None


class ApprovalListQuery(BaseModel):
    model_config = ConfigDict(extra="forbid")

    box: Literal["incoming", "outgoing"] | None = None


class ApprovalActionResult(BaseModel):
    model_config = ConfigDict(extra="forbid")

    approval_request: ApprovalRequestRead
    task: dict[str, Any] | None = None
    comment: dict[str, Any] | None = None
    cursor: int | None = None

    @property
    def request(self) -> ApprovalRequestRead:
        return self.approval_request


# Keep the naming aliases close to the existing task schemas.  HTTP routing is
# added in a later slice, and these aliases let callers choose either the
# concise or resource-oriented spelling without duplicating models.
CreateApprovalRequest = ApprovalRequestCreate
ApprovalRequest = ApprovalRequestRead
TaskApprovalRequestCreate = ApprovalRequestCreate
TaskApprovalCreateRequest = ApprovalRequestCreate
CreateTaskApprovalRequest = ApprovalRequestCreate
TaskApprovalActionRequest = ApprovalActionRequest
ApprovalRequestAction = ApprovalActionRequest
TaskApprovalRejectRequest = ApprovalRejectRequest
RejectApprovalRequest = ApprovalRejectRequest
TaskApprovalRequestSchema = ApprovalRequestRead
TaskApprovalResponse = ApprovalActionResult
TaskApprovalRequestResponse = ApprovalRequestRead


__all__ = [
    "ApprovalActionRequest",
    "ApprovalActionResult",
    "ApprovalListQuery",
    "ApprovalRejectRequest",
    "ApprovalRequestCreate",
    "ApprovalRequestRead",
    "ApprovalRequest",
    "ApprovalRequestAction",
    "CreateTaskApprovalRequest",
    "CreateApprovalRequest",
    "RejectApprovalRequest",
    "TaskApprovalActionRequest",
    "TaskApprovalRequestCreate",
    "TaskApprovalCreateRequest",
    "TaskApprovalRejectRequest",
    "TaskApprovalRequestSchema",
    "TaskApprovalRequestResponse",
    "TaskApprovalResponse",
]
