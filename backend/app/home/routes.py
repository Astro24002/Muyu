from __future__ import annotations

import base64
import binascii
import json
from datetime import datetime, timedelta, timezone
from typing import Any
from uuid import UUID

from fastapi import APIRouter, Depends, Query
from sqlalchemy import and_, case, func, or_, select
from sqlalchemy.orm import Session

from app.db.enums import (
    MembershipStatus,
    TaskApprovalRequestStatus,
    TaskApprovalRequestType,
    TaskStatus,
)
from app.core.time import BUSINESS_TIMEZONE_NAME, utc_week_bounds
from app.db.models import Task, TaskApprovalRequest, WorkspaceMembership
from app.home.schemas import (
    HomeApprovalItem,
    HomeApprovalSection,
    HomeEntries,
    HomeEntriesPage,
    HomeEntryName,
    HomeEntryCounts,
    HomeResponse,
    HomeTaskSection,
    HomeWeek,
    MomentProjection,
)
from app.httpapi.dependencies import get_db
from app.httpapi.errors import ApiError
from app.tasks.routes import Actor, require_actor
from app.tasks.approval_schemas import approval_request_json
from app.tasks.service import TaskService


router = APIRouter(prefix="/api/v1", tags=["home"])

_CURRENT_LIMIT = 5
_BLOCKED_LIMIT = 3
_REVIEW_LIMIT = 3
_ENTRY_LIMIT = 5
_MOMENT_BLOCKED_LIMIT = 3
_MOMENT_MINE_LIMIT = 5
_MOMENT_OTHER_LIMIT = 5
_ENTRY_PAGE_LIMIT = 500
_ENTRY_CURSOR_PREFIX = "home-entry-v1."
_MOMENT_PROGRESS_STATUSES = (TaskStatus.TODO, TaskStatus.IN_PROGRESS)
_WEEK_DUE_STATUSES = (
    TaskStatus.TODO,
    TaskStatus.IN_PROGRESS,
    TaskStatus.BLOCKED,
    TaskStatus.REVIEW,
)


@router.get("/home", response_model=HomeResponse)
def get_home(
    actor: Actor = Depends(require_actor),
    session: Session = Depends(get_db),
) -> HomeResponse:
    """Return compatibility action lists and the deduplicated moment projection."""

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
    pending_approval_count = _pending_approval_count(
        session,
        actor.workspace_id,
        approver_id=actor.user_id,
    )
    waiting_on_other_count = _pending_approval_count(
        session,
        actor.workspace_id,
        requester_id=actor.user_id,
    )

    # Count each pending agreement request once, including invitations that
    # have no task until the recipient accepts.
    needs_me_count = _pending_approval_count(
        session,
        actor.workspace_id,
        approver_id=actor.user_id,
        action_only=True,
    )
    waiting_on_other_entry_count = _pending_approval_count(
        session,
        actor.workspace_id,
        requester_id=actor.user_id,
        action_only=True,
    )
    needs_me_entries, needs_me_has_more = _pending_approval_entries(
        session,
        actor.workspace_id,
        approver_id=actor.user_id,
        limit=_ENTRY_LIMIT,
        action_only=True,
    )
    waiting_on_other_entries, waiting_on_other_has_more = _pending_approval_entries(
        session,
        actor.workspace_id,
        requester_id=actor.user_id,
        limit=_ENTRY_LIMIT,
        action_only=True,
    )

    # Read the live task set once so a task can only be assigned to one
    # moment section. The compatibility lists above intentionally retain their
    # historical independent bounds and viewer-only semantics.
    active_member_ids = list(
        session.scalars(
            select(WorkspaceMembership.user_id)
            .where(
                WorkspaceMembership.workspace_id == actor.workspace_id,
                WorkspaceMembership.status == MembershipStatus.ACTIVE,
            )
            .order_by(WorkspaceMembership.member_slot, WorkspaceMembership.user_id)
        ).all()
    )
    other_user_id = None
    if len(active_member_ids) == 2:
        other_user_id = next(
            (user_id for user_id in active_member_ids if user_id != actor.user_id),
            None,
        )
    live_tasks = session.scalars(
        select(Task).where(
            Task.workspace_id == actor.workspace_id,
            Task.deleted_at.is_(None),
        )
    ).all()

    moment_blocked = [
        task
        for task in live_tasks
        if task.status == TaskStatus.BLOCKED
        and task.current_handler_id in active_member_ids
    ]
    moment_mine = [
        task
        for task in live_tasks
        if task.status in _MOMENT_PROGRESS_STATUSES
        and task.current_handler_id == actor.user_id
    ]
    moment_other = [
        task
        for task in live_tasks
        if task.status in _MOMENT_PROGRESS_STATUSES
        and other_user_id is not None
        and task.current_handler_id == other_user_id
    ]
    for tasks, include_blocked_since in (
        (moment_blocked, True),
        (moment_mine, False),
        (moment_other, False),
    ):
        tasks.sort(key=lambda task: _task_sort_key(task, now, include_blocked_since=include_blocked_since))

    # Canonical moment sections are bounded independently so a large group
    # cannot crowd out the other questions. Keep the complete sorted lists for
    # the legacy aliases below, whose historical contract is unbounded.
    canonical_blocked = moment_blocked[:_MOMENT_BLOCKED_LIMIT]
    canonical_mine = moment_mine[:_MOMENT_MINE_LIMIT]
    canonical_other = moment_other[:_MOMENT_OTHER_LIMIT]
    canonical_moment_task_ids = {
        task.id
        for task in (*canonical_blocked, *canonical_mine, *canonical_other)
    }

    week_start, week_end = _week_bounds(now)
    week_due_count = _due_this_week_count(
        session,
        actor.workspace_id,
        week_start,
        week_end,
    )
    due_this_week, due_this_week_has_more = _bounded_tasks(
        session,
        select(Task).where(
            Task.workspace_id == actor.workspace_id,
            Task.deleted_at.is_(None),
            Task.status.in_(_WEEK_DUE_STATUSES),
            Task.due_at >= week_start,
            Task.due_at < week_end,
        ),
        _ENTRY_LIMIT,
        now,
        include_blocked_since=False,
    )

    moment_blocked_section = HomeTaskSection(
        items=[task_service.snapshot(task) for task in canonical_blocked],
        has_more=len(moment_blocked) > _MOMENT_BLOCKED_LIMIT,
    )
    moment_mine_section = HomeTaskSection(
        items=[task_service.snapshot(task) for task in canonical_mine],
        has_more=len(moment_mine) > _MOMENT_MINE_LIMIT,
    )
    moment_other_section = HomeTaskSection(
        items=[task_service.snapshot(task) for task in canonical_other],
        has_more=len(moment_other) > _MOMENT_OTHER_LIMIT,
    )
    legacy_moment_blocked_section = HomeTaskSection(
        items=[task_service.snapshot(task) for task in moment_blocked],
    )
    legacy_moment_mine_section = HomeTaskSection(
        items=[task_service.snapshot(task) for task in moment_mine],
    )
    legacy_moment_other_section = HomeTaskSection(
        items=[task_service.snapshot(task) for task in moment_other],
    )

    return HomeResponse(
        viewer_user_id=actor.user_id,
        as_of=now,
        week=HomeWeek(timezone=BUSINESS_TIMEZONE_NAME, start=week_start, end=week_end),
        entry_counts=HomeEntryCounts(
            needs_me=needs_me_count,
            waiting_on_other=waiting_on_other_entry_count,
            due_this_week=week_due_count,
        ),
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
        moment=MomentProjection(
            blocked=moment_blocked_section,
            mine=moment_mine_section,
            other=moment_other_section,
            blocked_tasks=legacy_moment_blocked_section,
            my_tasks=legacy_moment_mine_section,
            other_tasks=legacy_moment_other_section,
            all_tasks_has_more=len(canonical_moment_task_ids) < len(live_tasks),
        ),
        needs_action_count=pending_approval_count,
        waiting_on_other_count=waiting_on_other_count,
        week_due_count=week_due_count,
        entries=HomeEntries(
            needs_me=HomeApprovalSection(
                items=[
                    HomeApprovalItem(
                        approval_request=approval_request_json(request),
                        task=task_service.snapshot(task) if task is not None else None,
                    )
                    for request, task in needs_me_entries
                ],
                has_more=needs_me_has_more,
            ),
            waiting_on_other=HomeApprovalSection(
                items=[
                    HomeApprovalItem(
                        approval_request=approval_request_json(request),
                        task=task_service.snapshot(task) if task is not None else None,
                    )
                    for request, task in waiting_on_other_entries
                ],
                has_more=waiting_on_other_has_more,
            ),
            due_this_week=HomeTaskSection(
                items=[task_service.snapshot(task) for task in due_this_week],
                has_more=due_this_week_has_more,
            ),
        ),
    )


@router.get("/home/entries/{entry}", response_model=HomeEntriesPage)
def get_home_entry_page(
    entry: HomeEntryName,
    limit: int = Query(default=50, ge=1, le=_ENTRY_PAGE_LIMIT),
    after_cursor: str | None = Query(default=None),
    actor: Actor = Depends(require_actor),
    session: Session = Depends(get_db),
) -> HomeEntriesPage:
    """Return a stable keyset page for one canonical home entry.

    ``after_cursor`` is an opaque list cursor, deliberately separate from the
    workspace changes cursor.  ``0`` is accepted as an initial-page alias for
    clients that use the same convention as the changes endpoint.
    """

    cursor = _decode_entry_cursor(
        after_cursor,
        entry=entry,
        workspace_id=actor.workspace_id,
        viewer_id=actor.user_id,
    )
    task_service = TaskService(session)

    if entry in {"needs_me", "waiting_on_other"}:
        approver_id = actor.user_id if entry == "needs_me" else None
        requester_id = actor.user_id if entry == "waiting_on_other" else None
        count = _pending_approval_count(
            session,
            actor.workspace_id,
            approver_id=approver_id,
            requester_id=requester_id,
            action_only=True,
        )
        rows, has_more = _pending_approval_page(
            session,
            actor.workspace_id,
            approver_id=approver_id,
            requester_id=requester_id,
            limit=limit,
            cursor=cursor,
            action_only=True,
        )
        items = [
            HomeApprovalItem(
                approval_request=approval_request_json(request),
                task=task_service.snapshot(task) if task is not None else None,
            ).model_dump(mode="json")
            for request, task in rows
        ]
        next_cursor = None
        if has_more and rows:
            request = rows[-1][0]
            next_cursor = _encode_entry_cursor(
                entry=entry,
                workspace_id=actor.workspace_id,
                viewer_id=actor.user_id,
                after={
                    "created_at": _iso_utc(request.created_at),
                    "id": str(request.id),
                },
            )
    else:
        now, week_start, week_end = _entry_window(cursor)
        count = _due_this_week_count(session, actor.workspace_id, week_start, week_end)
        tasks, has_more = _due_this_week_page(
            session,
            actor.workspace_id,
            limit=limit,
            now=now,
            week_start=week_start,
            week_end=week_end,
            cursor=cursor,
        )
        items = [task_service.snapshot(task) for task in tasks]
        next_cursor = None
        if has_more and tasks:
            task = tasks[-1]
            next_cursor = _encode_entry_cursor(
                entry=entry,
                workspace_id=actor.workspace_id,
                viewer_id=actor.user_id,
                as_of=now,
                week_start=week_start,
                week_end=week_end,
                after=_task_cursor_key(task, now),
            )

    return HomeEntriesPage(
        count=count,
        items=items,
        has_more=has_more,
        next_cursor=next_cursor,
    )


def _encode_entry_cursor(
    *,
    entry: HomeEntryName,
    workspace_id: UUID,
    viewer_id: UUID,
    after: dict[str, Any],
    as_of: datetime | None = None,
    week_start: datetime | None = None,
    week_end: datetime | None = None,
) -> str:
    payload: dict[str, Any] = {
        "v": 1,
        "entry": entry,
        "workspace_id": str(workspace_id),
        "viewer_id": str(viewer_id),
        "after": after,
    }
    if as_of is not None:
        payload["as_of"] = _iso_utc(as_of)
    if week_start is not None:
        payload["week_start"] = _iso_utc(week_start)
    if week_end is not None:
        payload["week_end"] = _iso_utc(week_end)
    raw = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8")
    encoded = base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")
    return f"{_ENTRY_CURSOR_PREFIX}{encoded}"


def _decode_entry_cursor(
    value: str | None,
    *,
    entry: HomeEntryName,
    workspace_id: UUID,
    viewer_id: UUID,
) -> dict[str, Any] | None:
    if value is None or value == "0":
        return None
    if not value.startswith(_ENTRY_CURSOR_PREFIX):
        _invalid_entry_cursor()
    encoded = value[len(_ENTRY_CURSOR_PREFIX) :]
    if not encoded:
        _invalid_entry_cursor()
    try:
        raw = base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4))
        payload = json.loads(raw)
    except (binascii.Error, UnicodeDecodeError, ValueError, json.JSONDecodeError):
        _invalid_entry_cursor()
    if not isinstance(payload, dict):
        _invalid_entry_cursor()
    if (
        payload.get("v") != 1
        or payload.get("entry") != entry
        or payload.get("workspace_id") != str(workspace_id)
        or payload.get("viewer_id") != str(viewer_id)
        or not isinstance(payload.get("after"), dict)
    ):
        _invalid_entry_cursor()
    return payload


def _invalid_entry_cursor() -> None:
    raise ApiError(422, "invalid_home_cursor", "invalid home entry cursor")


def _entry_window(
    cursor: dict[str, Any] | None,
) -> tuple[datetime, datetime, datetime]:
    """Use the first page's time window for every later due-task page."""

    if cursor is None:
        now = datetime.now(timezone.utc)
        week_start, week_end = _week_bounds(now)
        return now, week_start, week_end
    now = _cursor_datetime(cursor.get("as_of"))
    week_start = _cursor_datetime(cursor.get("week_start"))
    week_end = _cursor_datetime(cursor.get("week_end"))
    if week_end - week_start != timedelta(days=7):
        _invalid_entry_cursor()
    return now, week_start, week_end


def _cursor_datetime(value: object) -> datetime:
    if not isinstance(value, str):
        _invalid_entry_cursor()
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        _invalid_entry_cursor()
    if parsed.tzinfo is None:
        _invalid_entry_cursor()
    return parsed.astimezone(timezone.utc)


def _cursor_uuid(value: object) -> UUID:
    if not isinstance(value, str):
        _invalid_entry_cursor()
    try:
        return UUID(value)
    except (ValueError, AttributeError):
        _invalid_entry_cursor()


def _pending_approval_page(
    session: Session,
    workspace_id,
    *,
    approver_id=None,
    requester_id=None,
    limit: int,
    cursor: dict[str, Any] | None,
    action_only: bool = False,
) -> tuple[list[tuple[TaskApprovalRequest, Task | None]], bool]:
    """Return one keyset page using the same visibility predicate as counts."""

    if (approver_id is None) == (requester_id is None):
        raise ValueError("exactly one pending approval direction is required")
    direction = (
        TaskApprovalRequest.approver_id == approver_id
        if approver_id is not None
        else TaskApprovalRequest.requester_id == requester_id
    )
    statement = select(TaskApprovalRequest, Task)
    if action_only:
        statement = statement.outerjoin(Task, Task.id == TaskApprovalRequest.task_id).where(
            or_(
                and_(TaskApprovalRequest.request_type == TaskApprovalRequestType.TASK_INVITATION, TaskApprovalRequest.task_id.is_(None)),
                and_(Task.workspace_id == workspace_id, Task.deleted_at.is_(None)),
            ),
            _task_action_request_predicate(),
        )
    else:
        statement = statement.outerjoin(Task, Task.id == TaskApprovalRequest.task_id).where(
            or_(
                TaskApprovalRequest.task_id.is_(None),
                and_(
                    Task.workspace_id == workspace_id,
                    Task.deleted_at.is_(None),
                ),
            ),
        )
    statement = statement.where(
        TaskApprovalRequest.workspace_id == workspace_id,
        TaskApprovalRequest.status == TaskApprovalRequestStatus.PENDING,
        direction,
    )
    if cursor is not None:
        after = cursor["after"]
        if not isinstance(after, dict):
            _invalid_entry_cursor()
        created_at = _cursor_datetime(after.get("created_at"))
        request_id = _cursor_uuid(after.get("id"))
        statement = statement.where(
            or_(
                TaskApprovalRequest.created_at > created_at,
                and_(
                    TaskApprovalRequest.created_at == created_at,
                    TaskApprovalRequest.id > request_id,
                ),
            )
        )
    rows = session.execute(
        statement.order_by(
            TaskApprovalRequest.created_at.asc(),
            TaskApprovalRequest.id.asc(),
        ).limit(limit + 1)
    ).all()
    return rows[:limit], len(rows) > limit


def _due_this_week_count(
    session: Session,
    workspace_id,
    week_start: datetime,
    week_end: datetime,
) -> int:
    count = session.scalar(
        select(func.count())
        .select_from(Task)
        .where(
            Task.workspace_id == workspace_id,
            Task.deleted_at.is_(None),
            Task.status.in_(_WEEK_DUE_STATUSES),
            Task.due_at >= week_start,
            Task.due_at < week_end,
        )
    )
    return int(count or 0)


def _due_this_week_page(
    session: Session,
    workspace_id,
    *,
    limit: int,
    now: datetime,
    week_start: datetime,
    week_end: datetime,
    cursor: dict[str, Any] | None,
) -> tuple[list[Task], bool]:
    overdue = case((and_(Task.due_at.is_not(None), Task.due_at < now), 0), else_=1)
    undated = case((Task.due_at.is_(None), 1), else_=0)
    statement = select(Task).where(
        Task.workspace_id == workspace_id,
        Task.deleted_at.is_(None),
        Task.status.in_(_WEEK_DUE_STATUSES),
        Task.due_at >= week_start,
        Task.due_at < week_end,
    )
    if cursor is not None:
        after = cursor["after"]
        if not isinstance(after, dict):
            _invalid_entry_cursor()
        after_overdue = after.get("overdue")
        after_undated = after.get("undated")
        if (
            type(after_overdue) is not int
            or after_overdue not in (0, 1)
            or type(after_undated) is not int
            or after_undated not in (0, 1)
        ):
            _invalid_entry_cursor()
        after_due_at = _cursor_datetime(after.get("due_at"))
        after_updated_at = _cursor_datetime(after.get("updated_at"))
        after_id = _cursor_uuid(after.get("id"))
        statement = statement.where(
            or_(
                overdue > after_overdue,
                and_(
                    overdue == after_overdue,
                    undated > after_undated,
                ),
                and_(
                    overdue == after_overdue,
                    undated == after_undated,
                    Task.due_at > after_due_at,
                ),
                and_(
                    overdue == after_overdue,
                    undated == after_undated,
                    Task.due_at == after_due_at,
                    Task.updated_at < after_updated_at,
                ),
                and_(
                    overdue == after_overdue,
                    undated == after_undated,
                    Task.due_at == after_due_at,
                    Task.updated_at == after_updated_at,
                    Task.id > after_id,
                ),
            )
        )
    rows = session.scalars(
        statement.order_by(
            overdue.asc(),
            undated.asc(),
            Task.due_at.asc(),
            Task.updated_at.desc(),
            Task.id.asc(),
        ).limit(limit + 1)
    ).all()
    return rows[:limit], len(rows) > limit


def _task_cursor_key(task: Task, now: datetime) -> dict[str, Any]:
    due_at = _as_utc(task.due_at)
    updated_at = _as_utc(task.updated_at)
    return {
        "overdue": 0 if due_at is not None and due_at < now else 1,
        "undated": 1 if due_at is None else 0,
        "due_at": _iso_utc(due_at),
        "updated_at": _iso_utc(updated_at),
        "id": str(task.id),
    }


def _week_bounds(now: datetime) -> tuple[datetime, datetime]:
    return utc_week_bounds(now)


def _iso_utc(value: datetime | None) -> str | None:
    normalized = _as_utc(value)
    return normalized.isoformat() if normalized is not None else None


def _pending_approval_count(
    session: Session,
    workspace_id,
    *,
    approver_id=None,
    requester_id=None,
    require_task: bool = False,
    action_only: bool = False,
) -> int:
    """Count pending requests whose task target is still visible."""

    if (approver_id is None) == (requester_id is None):
        raise ValueError("exactly one pending approval direction is required")
    direction = (
        TaskApprovalRequest.approver_id == approver_id
        if approver_id is not None
        else TaskApprovalRequest.requester_id == requester_id
    )
    statement = select(func.count()).select_from(TaskApprovalRequest)
    if require_task:
        statement = statement.join(Task, Task.id == TaskApprovalRequest.task_id)
        target = and_(
            Task.workspace_id == workspace_id,
            Task.deleted_at.is_(None),
        )
    else:
        statement = statement.outerjoin(Task, Task.id == TaskApprovalRequest.task_id)
        target = or_(
            and_(TaskApprovalRequest.task_id.is_(None), TaskApprovalRequest.request_type == TaskApprovalRequestType.TASK_INVITATION) if action_only else TaskApprovalRequest.task_id.is_(None),
            and_(
                Task.workspace_id == workspace_id,
                Task.deleted_at.is_(None),
            ),
        )
    filters = [
        TaskApprovalRequest.workspace_id == workspace_id,
        TaskApprovalRequest.status == TaskApprovalRequestStatus.PENDING,
        direction,
        target,
    ]
    if action_only:
        filters.append(_task_action_request_predicate())
    count = session.scalar(statement.where(*filters))
    return int(count or 0)


def _pending_approval_entries(
    session: Session,
    workspace_id,
    *,
    approver_id=None,
    requester_id=None,
    limit: int,
    action_only: bool = False,
) -> tuple[list[tuple[TaskApprovalRequest, Task | None]], bool]:
    """Return bounded pending request/task pairs in stable oldest-first order."""

    if (approver_id is None) == (requester_id is None):
        raise ValueError("exactly one pending approval direction is required")
    direction = (
        TaskApprovalRequest.approver_id == approver_id
        if approver_id is not None
        else TaskApprovalRequest.requester_id == requester_id
    )
    statement = select(TaskApprovalRequest, Task)
    if action_only:
        statement = statement.outerjoin(Task, Task.id == TaskApprovalRequest.task_id).where(
            or_(
                and_(TaskApprovalRequest.request_type == TaskApprovalRequestType.TASK_INVITATION, TaskApprovalRequest.task_id.is_(None)),
                and_(Task.workspace_id == workspace_id, Task.deleted_at.is_(None)),
            ),
            _task_action_request_predicate(),
        )
    else:
        statement = statement.outerjoin(Task, Task.id == TaskApprovalRequest.task_id).where(
            or_(
                TaskApprovalRequest.task_id.is_(None),
                and_(
                    Task.workspace_id == workspace_id,
                    Task.deleted_at.is_(None),
                ),
            ),
        )
    rows = session.execute(
        statement.where(
            TaskApprovalRequest.workspace_id == workspace_id,
            TaskApprovalRequest.status == TaskApprovalRequestStatus.PENDING,
            direction,
        )
        .order_by(
            TaskApprovalRequest.created_at.asc(),
            TaskApprovalRequest.id.asc(),
        )
        .limit(limit + 1)
    ).all()
    return rows[:limit], len(rows) > limit


def _task_action_request_predicate():
    """Match only the live requests that make another member the next actor."""

    return or_(
        TaskApprovalRequest.request_type.in_((
            TaskApprovalRequestType.TASK_INVITATION,
            TaskApprovalRequestType.TASK_UPDATE,
            TaskApprovalRequestType.QUADRANT_UPDATE,
            TaskApprovalRequestType.TASK_DELETE,
        )),
        TaskApprovalRequest.request_type == TaskApprovalRequestType.HANDLER_TRANSFER,
        and_(
            TaskApprovalRequest.request_type == TaskApprovalRequestType.STATUS_UPDATE,
            TaskApprovalRequest.proposed_changes.contains(
                {
                    "target_status": TaskStatus.DONE.value,
                    "review_submission": True,
                }
            ),
            Task.status == TaskStatus.REVIEW,
            Task.current_handler_id == TaskApprovalRequest.requester_id,
            Task.reviewer_user_id == TaskApprovalRequest.approver_id,
        ),
    )


def _task_sort_key(
    task: Task,
    now: datetime,
    *,
    include_blocked_since: bool,
) -> tuple[object, ...]:
    """Match the compatibility ordering while keeping moment ordering local."""

    due_at = _as_utc(task.due_at)
    updated_at = _as_utc(task.updated_at)
    overdue = due_at is not None and due_at < now
    key: tuple[object, ...] = (
        0 if overdue else 1,
        1 if due_at is None else 0,
        due_at.timestamp() if due_at is not None else float("inf"),
    )
    if include_blocked_since:
        blocked_since = _as_utc(task.blocked_since)
        key += (
            1 if blocked_since is None else 0,
            blocked_since.timestamp() if blocked_since is not None else float("inf"),
        )
    return key + (
        -(updated_at.timestamp() if updated_at is not None else float("-inf")),
        str(task.id),
    )


def _as_utc(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


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
