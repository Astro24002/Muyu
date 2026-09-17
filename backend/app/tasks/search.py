from __future__ import annotations

import base64
import binascii
from dataclasses import dataclass
from datetime import datetime, timezone
import json
from uuid import UUID

from sqlalchemy import String, and_, cast, exists, func, or_, select
from sqlalchemy.orm import Session

from app.db.enums import MembershipStatus, TaskApprovalRequestStatus, TaskApprovalRequestType, TaskStatus
from app.db.models import Task, TaskApprovalRequest, User, WorkspaceMembership
from app.httpapi.errors import ApiError


_TASK_QUERY_CURSOR_PREFIX = "task-query-v1."
_OPEN_STATUSES = (TaskStatus.TODO, TaskStatus.IN_PROGRESS, TaskStatus.BLOCKED, TaskStatus.REVIEW)
_STATUS_ALIASES = {
    "open": "open",
    "all": "all",
    "blocked": "blocked",
    "review": "review",
    "done": "done",
    "cancelled": "cancelled",
    "handoff_pending": "handoff_pending",
}


@dataclass(frozen=True)
class TaskQueryPage:
    tasks: list[Task]
    has_more: bool
    next_cursor: str | None
    query: dict[str, object]


def search_tasks(session: Session, workspace_id: UUID, query: str, limit: int = 50) -> list[Task]:
    needle = f"%{query.strip()}%"
    return list(session.scalars(select(Task).where(Task.workspace_id == workspace_id, Task.deleted_at.is_(None), or_(Task.title.ilike(needle), Task.description.ilike(needle))).order_by(Task.updated_at.desc()).limit(min(100, max(1, limit)))))


def query_tasks(
    session: Session,
    workspace_id: UUID,
    viewer_id: UUID,
    *,
    q: str | None = None,
    status: str | None = None,
    handler: str | None = None,
    include_history: bool = False,
    limit: int = 50,
    after: str | None = None,
) -> TaskQueryPage:
    """Return a workspace-scoped keyset page over the canonical task set."""

    normalized_q = _normalize_query_text(q)
    normalized_status = _normalize_status(status, include_history)
    normalized_handler = _normalize_handler(handler)
    query_summary: dict[str, object] = {
        "q": normalized_q,
        "status": normalized_status,
        "handler": normalized_handler,
        "include_history": normalized_status == "all" and status is None and include_history,
    }

    statement = (
        select(Task)
        .outerjoin(User, User.id == Task.current_handler_id)
        .where(
            Task.workspace_id == workspace_id,
            Task.deleted_at.is_(None),
        )
    )

    if normalized_q is not None:
        needle = f"%{normalized_q}%"
        statement = statement.where(
            or_(
                Task.title.ilike(needle),
                Task.description.ilike(needle),
                Task.next_step_text.ilike(needle),
                cast(Task.labels, String).ilike(needle),
                func.coalesce(User.display_name, "").ilike(needle),
            )
        )

    if normalized_status == "open":
        statement = statement.where(Task.status.in_(_OPEN_STATUSES))
    elif normalized_status == "blocked":
        statement = statement.where(Task.status == TaskStatus.BLOCKED)
    elif normalized_status == "review":
        statement = statement.where(Task.status == TaskStatus.REVIEW)
    elif normalized_status == "done":
        statement = statement.where(Task.status == TaskStatus.DONE)
    elif normalized_status == "cancelled":
        statement = statement.where(Task.status == TaskStatus.CANCELLED)
    elif normalized_status == "handoff_pending":
        statement = statement.where(
            exists(
                select(1).where(
                    TaskApprovalRequest.workspace_id == workspace_id,
                    TaskApprovalRequest.task_id == Task.id,
                    TaskApprovalRequest.status == TaskApprovalRequestStatus.PENDING,
                    TaskApprovalRequest.request_type == TaskApprovalRequestType.HANDLER_TRANSFER,
                )
            )
        )

    statement = _apply_handler_filter(
        statement,
        session,
        workspace_id,
        viewer_id,
        normalized_handler,
    )

    cursor = _decode_task_query_cursor(after, workspace_id, viewer_id, query_summary)
    if cursor is not None:
        cursor_updated_at = _cursor_datetime(cursor["updated_at"])
        cursor_task_id = _cursor_uuid(cursor["id"])
        statement = statement.where(
            or_(
                Task.updated_at < cursor_updated_at,
                and_(Task.updated_at == cursor_updated_at, Task.id > cursor_task_id),
            )
        )

    page_limit = min(100, max(1, limit))
    rows = session.scalars(
        statement.order_by(Task.updated_at.desc(), Task.id.asc()).limit(page_limit + 1)
    ).all()
    tasks = rows[:page_limit]
    has_more = len(rows) > page_limit
    next_cursor = None
    if has_more and tasks:
        last = tasks[-1]
        next_cursor = _encode_task_query_cursor(
            workspace_id,
            viewer_id,
            query_summary,
            updated_at=last.updated_at,
            task_id=last.id,
        )
    return TaskQueryPage(tasks, has_more, next_cursor, query_summary)


def _normalize_query_text(value: str | None) -> str | None:
    if value is None:
        return None
    normalized = " ".join(value.split())
    if len(normalized) > 200:
        raise ApiError(422, "invalid_task_query", "q must be at most 200 characters")
    return normalized or None


def _normalize_status(value: str | None, include_history: bool) -> str:
    if value is None or not value.strip():
        return "all" if include_history else "open"
    normalized = value.strip().lower()
    if normalized not in _STATUS_ALIASES:
        raise ApiError(422, "invalid_task_query", "unsupported task status filter")
    return _STATUS_ALIASES[normalized]


def _normalize_handler(value: str | None) -> str:
    if value is None or not value.strip():
        return "all"
    normalized = value.strip().lower()
    aliases = {
        "me": "mine",
        "mine": "mine",
        "other": "other",
        "ta": "other",
        "all": "all",
        "unassigned": "unassigned",
    }
    if normalized in aliases:
        return aliases[normalized]
    try:
        UUID(normalized)
    except ValueError as error:
        raise ApiError(422, "invalid_task_query", "unsupported task handler filter") from error
    return normalized


def _apply_handler_filter(statement, session: Session, workspace_id: UUID, viewer_id: UUID, handler: str):
    if handler == "mine":
        return statement.where(Task.current_handler_id == viewer_id)
    if handler == "unassigned":
        return statement.where(Task.current_handler_id.is_(None))
    if handler == "other":
        other_id = session.scalar(
            select(WorkspaceMembership.user_id)
            .where(
                WorkspaceMembership.workspace_id == workspace_id,
                WorkspaceMembership.status == MembershipStatus.ACTIVE,
                WorkspaceMembership.user_id != viewer_id,
            )
            .order_by(WorkspaceMembership.member_slot, WorkspaceMembership.user_id)
        )
        if other_id is None:
            return statement.where(False)
        return statement.where(Task.current_handler_id == other_id)
    if handler != "all":
        return statement.where(Task.current_handler_id == UUID(handler))
    return statement


def _encode_task_query_cursor(
    workspace_id: UUID,
    viewer_id: UUID,
    query: dict[str, object],
    *,
    updated_at: datetime,
    task_id: UUID,
) -> str:
    payload = {
        "v": 1,
        "workspace_id": str(workspace_id),
        "viewer_id": str(viewer_id),
        "query": query,
        "updated_at": _iso_utc(updated_at),
        "id": str(task_id),
    }
    raw = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8")
    encoded = base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")
    return f"{_TASK_QUERY_CURSOR_PREFIX}{encoded}"


def _decode_task_query_cursor(
    value: str | None,
    workspace_id: UUID,
    viewer_id: UUID,
    query: dict[str, object],
) -> dict[str, object] | None:
    if value is None or value == "":
        return None
    if not value.startswith(_TASK_QUERY_CURSOR_PREFIX):
        _invalid_task_cursor()
    encoded = value[len(_TASK_QUERY_CURSOR_PREFIX) :]
    try:
        raw = base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4))
        payload = json.loads(raw)
    except (binascii.Error, UnicodeDecodeError, ValueError, json.JSONDecodeError):
        _invalid_task_cursor()
    if (
        not isinstance(payload, dict)
        or payload.get("v") != 1
        or payload.get("workspace_id") != str(workspace_id)
        or payload.get("viewer_id") != str(viewer_id)
        or payload.get("query") != query
    ):
        _invalid_task_cursor()
    if not isinstance(payload.get("updated_at"), str) or not isinstance(payload.get("id"), str):
        _invalid_task_cursor()
    return payload


def _invalid_task_cursor() -> None:
    raise ApiError(422, "invalid_task_cursor", "invalid task query cursor")


def _cursor_datetime(value: object) -> datetime:
    if not isinstance(value, str):
        _invalid_task_cursor()
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        _invalid_task_cursor()
    if parsed.tzinfo is None:
        _invalid_task_cursor()
    return parsed.astimezone(timezone.utc)


def _cursor_uuid(value: object) -> UUID:
    if not isinstance(value, str):
        _invalid_task_cursor()
    try:
        return UUID(value)
    except ValueError:
        _invalid_task_cursor()


def _iso_utc(value: datetime | None) -> str | None:
    if value is None:
        return None
    normalized = value if value.tzinfo is not None else value.replace(tzinfo=timezone.utc)
    return normalized.astimezone(timezone.utc).isoformat()
