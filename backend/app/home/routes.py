from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends
from sqlalchemy import and_, case, func, select
from sqlalchemy.orm import Session

from app.db.enums import TaskApprovalRequestStatus, TaskStatus
from app.db.models import Task, TaskApprovalRequest
from app.home.schemas import HomeResponse, HomeTaskSection
from app.httpapi.dependencies import get_db
from app.tasks.routes import Actor, require_actor
from app.tasks.service import TaskService


router = APIRouter(prefix="/api/v1", tags=["home"])

_CURRENT_LIMIT = 5
_BLOCKED_LIMIT = 3
_REVIEW_LIMIT = 3


@router.get("/home", response_model=HomeResponse)
def get_home(
    actor: Actor = Depends(require_actor),
    session: Session = Depends(get_db),
) -> HomeResponse:
    """Return only the actions that need the current member's attention."""

    now = datetime.now(timezone.utc)
    task_service = TaskService(session)
    current_tasks, has_more_current = _bounded_tasks(
        session,
        select(Task).where(
            Task.workspace_id == actor.workspace_id,
            Task.deleted_at.is_(None),
            Task.current_handler_id == actor.user_id,
            Task.status.in_((TaskStatus.TODO, TaskStatus.IN_PROGRESS)),
        ),
        _CURRENT_LIMIT,
        now,
        include_blocked_since=False,
    )
    blocked_tasks, has_more_blocked = _bounded_tasks(
        session,
        select(Task).where(
            Task.workspace_id == actor.workspace_id,
            Task.deleted_at.is_(None),
            Task.current_handler_id == actor.user_id,
            Task.status == TaskStatus.BLOCKED,
        ),
        _BLOCKED_LIMIT,
        now,
        include_blocked_since=True,
    )
    review_tasks, has_more_review = _bounded_tasks(
        session,
        select(Task).where(
            Task.workspace_id == actor.workspace_id,
            Task.deleted_at.is_(None),
            Task.reviewer_user_id == actor.user_id,
            Task.current_handler_id != actor.user_id,
            Task.status == TaskStatus.REVIEW,
        ),
        _REVIEW_LIMIT,
        now,
        include_blocked_since=False,
    )
    pending_approval_count = int(
        session.scalar(
            select(func.count())
            .select_from(TaskApprovalRequest)
            .where(
                TaskApprovalRequest.workspace_id == actor.workspace_id,
                TaskApprovalRequest.approver_id == actor.user_id,
                TaskApprovalRequest.status == TaskApprovalRequestStatus.PENDING,
            )
        )
        or 0
    )

    return HomeResponse(
        current_tasks=HomeTaskSection(
            items=[task_service.snapshot(task) for task in current_tasks],
            has_more=has_more_current,
        ),
        blocked_tasks=HomeTaskSection(
            items=[task_service.snapshot(task) for task in blocked_tasks],
            has_more=has_more_blocked,
        ),
        review_tasks=HomeTaskSection(
            items=[task_service.snapshot(task) for task in review_tasks],
            has_more=has_more_review,
        ),
        pending_approval_count=pending_approval_count,
    )


def _bounded_tasks(
    session: Session,
    statement,
    limit: int,
    now: datetime,
    *,
    include_blocked_since: bool,
) -> tuple[list[Task], bool]:
    """Order a list once, then use one extra row to report truncation."""

    overdue = case((and_(Task.due_at.is_not(None), Task.due_at < now), 0), else_=1)
    undated = case((Task.due_at.is_(None), 1), else_=0)
    ordering = [overdue.asc(), undated.asc(), Task.due_at.asc()]
    if include_blocked_since:
        # Earlier non-null values have been blocked longer and take priority.
        ordering.append(Task.blocked_since.asc())
    ordering.extend((Task.updated_at.desc(), Task.id.asc()))
    rows = session.scalars(statement.order_by(*ordering).limit(limit + 1)).all()
    return rows[:limit], len(rows) > limit


__all__ = ["router"]
