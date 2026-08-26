from __future__ import annotations

from datetime import datetime, timezone
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.enums import ChangeAction, OperationType
from app.db.models import DelayRecord, Task
from app.tasks.conflicts import TaskConflictError
from app.tasks.operations import request_fingerprint
from app.tasks.service import TaskService


def add_delay(session: Session, workspace_id: UUID, actor_user_id: UUID, task_id: UUID, new_due_at: datetime, reason: str, note: str | None = None, request_id: UUID | None = None) -> DelayRecord:
    task = session.scalar(select(Task).where(Task.id == task_id, Task.workspace_id == workspace_id).with_for_update())
    if task is None:
        raise TaskConflictError("not_found", "task not found")
    if task.deleted_at is not None:
        raise TaskConflictError("lifecycle_conflict", "deleted task cannot be delayed")
    if new_due_at.tzinfo is None:
        new_due_at = new_due_at.replace(tzinfo=timezone.utc)
    service = TaskService(session)
    request_id = request_id or UUID(int=0)
    fingerprint = request_fingerprint(
        f"/api/v1/tasks/{task_id}/delays",
        {"new_due_at": new_due_at.isoformat(), "reason": reason, "note": note},
    )
    existing = service._existing_operation(workspace_id, actor_user_id, request_id)
    if existing is not None:
        if existing.base_versions != {"fingerprint": fingerprint}:
            raise TaskConflictError("idempotency_key_reused", "request id was used with a different payload")
        delay_id = (existing.after_state or {}).get("delay_id")
        record = session.get(DelayRecord, UUID(delay_id)) if delay_id else None
        if record is None:
            raise TaskConflictError("not_found", "delay record not found")
        return record
    current_due = task.due_at or datetime.now(timezone.utc)
    if new_due_at < current_due + __import__("datetime").timedelta(minutes=1):
        raise TaskConflictError("invalid_request", "new due date must be at least one minute later")
    if reason == "OTHER" and not (note or "").strip():
        raise TaskConflictError("invalid_request", "OTHER delay reason requires a note")
    before = service.snapshot(task)
    original = current_due
    record = DelayRecord(
        workspace_id=workspace_id,
        task_id=task_id,
        actor_user_id=actor_user_id,
        original_due_at=original,
        new_due_at=new_due_at,
        delayed_at=datetime.now(timezone.utc),
        delay_duration_minutes=max(0, int((new_due_at - original).total_seconds() // 60)),
        reason=reason,
        note=note,
    )
    task.due_at = new_due_at
    task.version += 1
    versions = dict(task.field_versions or {})
    versions["due_at"] = int(versions.get("due_at", 1)) + 1
    task.field_versions = versions
    session.add(record)
    session.flush()
    cursor = service._cursor(workspace_id, task, ChangeAction.UPDATED, request_id)
    service._operation(
        workspace_id,
        actor_user_id,
        request_id,
        task,
        OperationType.DELAYED,
        before,
        {"task": service.snapshot(task), "delay_id": str(record.id)},
        cursor,
        base_versions={"fingerprint": fingerprint},
    )
    return record


def list_delays(session: Session, workspace_id: UUID, task_id: UUID) -> list[DelayRecord]:
    return list(session.scalars(select(DelayRecord).where(DelayRecord.workspace_id == workspace_id, DelayRecord.task_id == task_id).order_by(DelayRecord.created_at)))
