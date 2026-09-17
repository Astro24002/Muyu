from __future__ import annotations

import calendar
from collections.abc import Callable
from datetime import date, datetime, time, timezone
from typing import Any
from uuid import UUID, uuid4

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.enums import AnniversaryKind, ChangeAction, TaskQuadrant, TaskStatus
from app.db.models import Anniversary, Task, WorkspaceClassification
from app.life.common import (
    BUSINESS_TIMEZONE,
    LifeError,
    active_member,
    allocate_resource_cursor,
    get_command,
    json_body,
    now_utc,
    parse_date,
    record_activity,
    save_command,
    workspace_today,
)
from app.tasks.service import TaskService


PREPARE_DAYS = {0, 1, 3, 7, 14, 30}
ALLOWED_KINDS = {item.value for item in AnniversaryKind}


def next_occurrence(anchor_date: date, today: date) -> date:
    """Return the next Gregorian occurrence, including leap-day handling."""
    if anchor_date > today:
        return anchor_date
    year = today.year
    while True:
        if anchor_date.month == 2 and anchor_date.day == 29 and not calendar.isleap(year):
            candidate = date(year, 2, 28)
        else:
            candidate = date(year, anchor_date.month, anchor_date.day)
        if candidate >= today:
            return candidate
        year += 1


class AnniversaryService:
    def __init__(self, session: Session, *, now: Callable[[], datetime] | None = None) -> None:
        self.session = session
        self.now = now
        self.last_cursor: int | None = None

    def create(self, workspace_id: UUID, actor_user_id: UUID, request_id: UUID, *, title: str, anchor_date: date, kind: AnniversaryKind, prepare_days: int, note: str | None) -> Anniversary:
        active_member(self.session, workspace_id, actor_user_id)
        payload = json_body({"title": title, "anchor_date": anchor_date, "kind": kind, "prepare_days": prepare_days, "note": note})
        command = get_command(self.session, workspace_id, actor_user_id, request_id, "/api/v1/anniversaries", payload)
        if command is not None:
            row = self.session.get(Anniversary, command.resource_id)
            if row is None:
                raise LifeError("not_found", "anniversary not found", 404)
            self.last_cursor = command.cursor
            return row
        title = title.strip()
        if not title:
            raise LifeError("invalid_request", "anniversary title is required")
        if prepare_days not in PREPARE_DAYS:
            raise LifeError("invalid_request", "prepare_days must be 0, 1, 3, 7, 14, or 30")
        try:
            normalized_kind = AnniversaryKind(kind)
        except ValueError as error:
            raise LifeError("invalid_request", "kind is invalid") from error
        row = Anniversary(
            id=uuid4(),
            workspace_id=workspace_id,
            title=title,
            anchor_date=anchor_date,
            kind=normalized_kind,
            prepare_days=prepare_days,
            note=note.strip() if isinstance(note, str) and note.strip() else None,
            created_by=actor_user_id,
            updated_by=actor_user_id,
        )
        self.session.add(row)
        self.session.flush()
        cursor = allocate_resource_cursor(self.session, workspace_id, "anniversary", row.id, ChangeAction.CREATED, request_id)
        record_activity(self.session, workspace_id, actor_user_id, "ANNIVERSARY_CREATED", {"anniversary_id": str(row.id), "after": self.snapshot(row)}, request_id)
        save_command(self.session, workspace_id, actor_user_id, request_id, "anniversary", row.id, cursor, "/api/v1/anniversaries", payload)
        self.last_cursor = cursor
        return row

    def patch(self, workspace_id: UUID, actor_user_id: UUID, anniversary_id: UUID, request_id: UUID, expected_version: int, changes: dict[str, Any]) -> Anniversary:
        payload = json_body({"anniversary_id": anniversary_id, "expected_version": expected_version, "changes": changes})
        command = get_command(self.session, workspace_id, actor_user_id, request_id, f"/api/v1/anniversaries/{anniversary_id}", payload)
        if command is not None:
            row = self.session.get(Anniversary, command.resource_id)
            if row is None:
                raise LifeError("not_found", "anniversary not found", 404)
            self.last_cursor = command.cursor
            return row
        active_member(self.session, workspace_id, actor_user_id)
        row = self._lock(workspace_id, anniversary_id)
        if row.deleted_at is not None:
            raise LifeError("lifecycle_conflict", "deleted anniversary cannot be edited", 409)
        if row.version != expected_version:
            raise LifeError("version_conflict", "anniversary has changed", 409)
        unknown = set(changes) - {"title", "anchor_date", "kind", "prepare_days", "note"}
        if unknown:
            raise LifeError("invalid_request", f"unknown anniversary fields: {sorted(unknown)}")
        before = self.snapshot(row)
        if "title" in changes:
            value = changes["title"]
            if not isinstance(value, str) or not value.strip() or len(value.strip()) > 160:
                raise LifeError("invalid_request", "anniversary title is required")
            row.title = value.strip()
        if "anchor_date" in changes:
            row.anchor_date = parse_date(changes["anchor_date"], "anchor_date")
        if "kind" in changes:
            try:
                row.kind = AnniversaryKind(str(changes["kind"]))
            except ValueError as error:
                raise LifeError("invalid_request", "kind is invalid") from error
        if "prepare_days" in changes:
            try:
                value = int(changes["prepare_days"])
            except (TypeError, ValueError) as error:
                raise LifeError("invalid_request", "prepare_days is invalid") from error
            if value not in PREPARE_DAYS:
                raise LifeError("invalid_request", "prepare_days must be 0, 1, 3, 7, 14, or 30")
            row.prepare_days = value
        if "note" in changes:
            value = changes["note"]
            if value is not None and (not isinstance(value, str) or len(value) > 5000):
                raise LifeError("invalid_request", "note is too long")
            row.note = value.strip() if isinstance(value, str) and value.strip() else None
        row.updated_by = actor_user_id
        row.version += 1
        self.session.flush()
        cursor = allocate_resource_cursor(self.session, workspace_id, "anniversary", row.id, ChangeAction.UPDATED, request_id)
        record_activity(self.session, workspace_id, actor_user_id, "ANNIVERSARY_UPDATED", {"anniversary_id": str(row.id), "before": before, "after": self.snapshot(row)}, request_id)
        save_command(self.session, workspace_id, actor_user_id, request_id, "anniversary", row.id, cursor, f"/api/v1/anniversaries/{anniversary_id}", payload)
        self.last_cursor = cursor
        return row

    def delete(self, workspace_id: UUID, actor_user_id: UUID, anniversary_id: UUID, request_id: UUID, expected_version: int, confirm: bool) -> Anniversary:
        payload = {"anniversary_id": str(anniversary_id), "expected_version": expected_version, "confirm": confirm}
        command = get_command(self.session, workspace_id, actor_user_id, request_id, f"/api/v1/anniversaries/{anniversary_id}/delete", payload)
        if command is not None:
            row = self.session.get(Anniversary, command.resource_id)
            if row is None:
                raise LifeError("not_found", "anniversary not found", 404)
            self.last_cursor = command.cursor
            return row
        if not confirm:
            raise LifeError("confirmation_required", "confirm anniversary deletion before continuing")
        active_member(self.session, workspace_id, actor_user_id)
        row = self._lock(workspace_id, anniversary_id)
        if row.deleted_at is not None:
            raise LifeError("lifecycle_conflict", "anniversary is already deleted", 409)
        if row.version != expected_version:
            raise LifeError("version_conflict", "anniversary has changed", 409)
        row.deleted_at = now_utc(self.now)
        row.deleted_by = actor_user_id
        row.updated_by = actor_user_id
        row.version += 1
        self.session.flush()
        cursor = allocate_resource_cursor(self.session, workspace_id, "anniversary", row.id, ChangeAction.DELETED, request_id)
        record_activity(self.session, workspace_id, actor_user_id, "ANNIVERSARY_DELETED", {"anniversary_id": str(row.id)}, request_id)
        save_command(self.session, workspace_id, actor_user_id, request_id, "anniversary", row.id, cursor, f"/api/v1/anniversaries/{anniversary_id}/delete", payload)
        self.last_cursor = cursor
        return row

    def list(self, workspace_id: UUID, viewer_id: UUID) -> list[dict[str, object]]:
        active_member(self.session, workspace_id, viewer_id)
        rows = self.session.scalars(
            select(Anniversary).where(Anniversary.workspace_id == workspace_id, Anniversary.deleted_at.is_(None)).order_by(Anniversary.anchor_date.asc(), Anniversary.id.asc())
        ).all()
        return [self.snapshot(row) for row in rows]

    def generate_preparation(self, workspace_id: UUID, actor_user_id: UUID, anniversary_id: UUID, request_id: UUID) -> Task:
        active_member(self.session, workspace_id, actor_user_id)
        row = self._lock(workspace_id, anniversary_id)
        if row.deleted_at is not None:
            raise LifeError("not_found", "anniversary not found", 404)
        occurrence = next_occurrence(row.anchor_date, workspace_today(self.now))
        source_key = f"anniversary:{row.id}:{occurrence.isoformat()}"
        payload = {"anniversary_id": str(row.id), "occurrence_date": occurrence.isoformat(), "source_key": source_key}
        command = get_command(self.session, workspace_id, actor_user_id, request_id, f"/api/v1/anniversaries/{anniversary_id}/prepare", payload)
        existing = self.session.scalar(select(Task).where(Task.workspace_id == workspace_id, Task.source_key == source_key))
        if existing is not None:
            if command is None:
                # A second command for the same occurrence is a successful
                # no-op and is recorded for retry safety without a new cursor.
                save_command(self.session, workspace_id, actor_user_id, request_id, "task", existing.id, 0, f"/api/v1/anniversaries/{anniversary_id}/prepare", payload)
            self.last_cursor = command.cursor if command is not None else None
            return existing
        if command is not None:
            raise LifeError("not_found", "generated preparation task not found", 404)
        classification = self.session.scalar(
            select(WorkspaceClassification).where(WorkspaceClassification.workspace_id == workspace_id).order_by(WorkspaceClassification.normalized_name.asc(), WorkspaceClassification.id.asc())
        )
        if classification is None:
            raise LifeError("invalid_request", "an approved task classification is required before generating a preparation task")
        due_at = datetime.combine(occurrence, time.max, tzinfo=BUSINESS_TIMEZONE).astimezone(timezone.utc)
        task_request = request_id
        task_service = TaskService(self.session, now=self.now or (lambda: datetime.now(timezone.utc)))
        task = task_service.create(
            workspace_id,
            actor_user_id,
            task_request,
            f"准备：{row.title}",
            row.note or "",
            due_at,
            None,
            None,
            None,
            TaskQuadrant.Q2.value,
            [classification.name],
            f"确认并准备“{row.title[:82]}”",
            source_key=source_key,
            initial_status=TaskStatus.IN_PROGRESS,
        )
        record_activity(self.session, workspace_id, actor_user_id, "ANNIVERSARY_PREPARATION_TASK_GENERATED", {"anniversary_id": str(row.id), "task_id": str(task.id), "source_key": source_key, "occurrence_date": occurrence.isoformat()}, request_id)
        # TaskService allocated the authoritative task cursor. Record the same
        # cursor on the domain command so a retry returns the existing task.
        task_cursor = task_service.last_cursor or 0
        save_command(self.session, workspace_id, actor_user_id, request_id, "task", task.id, task_cursor, f"/api/v1/anniversaries/{anniversary_id}/prepare", payload)
        self.last_cursor = task_cursor or None
        return task

    def _lock(self, workspace_id: UUID, anniversary_id: UUID) -> Anniversary:
        row = self.session.scalar(select(Anniversary).where(Anniversary.workspace_id == workspace_id, Anniversary.id == anniversary_id).with_for_update())
        if row is None:
            raise LifeError("not_found", "anniversary not found", 404)
        return row

    def snapshot(self, row: Anniversary) -> dict[str, object]:
        today = workspace_today(self.now)
        occurrence = next_occurrence(row.anchor_date, today)
        return {
            "id": str(row.id),
            "workspace_id": str(row.workspace_id),
            "title": row.title,
            "anchor_date": row.anchor_date.isoformat(),
            "kind": row.kind.value if hasattr(row.kind, "value") else str(row.kind),
            "prepare_days": row.prepare_days,
            "note": row.note,
            "next_occurrence": occurrence.isoformat(),
            "days_until": (occurrence - today).days,
            "is_today": occurrence == today,
            "version": row.version,
            "created_by": str(row.created_by),
            "updated_by": str(row.updated_by),
            "deleted_at": row.deleted_at.isoformat() if row.deleted_at else None,
            "created_at": row.created_at.isoformat() if row.created_at else None,
            "updated_at": row.updated_at.isoformat() if row.updated_at else None,
        }
