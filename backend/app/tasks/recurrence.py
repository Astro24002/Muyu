from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.enums import ChangeAction, OperationType, RecurrenceStatus
from app.db.models import RecurrenceRule, Task
from app.tasks.service import TaskService


SUPPORTED_RULES = {"DAILY", "WEEKLY", "MONTHLY"}


def create_rule(session: Session, workspace_id: UUID, actor_user_id: UUID, task_id: UUID, rule: str, request_id: UUID | None = None) -> RecurrenceRule:
    normalized = rule.upper().strip()
    if normalized.split(":", 1)[0] not in SUPPORTED_RULES:
        raise ValueError("recurrence must be DAILY, WEEKLY, or MONTHLY")
    if session.scalar(select(Task.id).where(Task.id == task_id, Task.workspace_id == workspace_id)) is None:
        raise ValueError("task not found")
    existing = session.scalar(select(RecurrenceRule).where(RecurrenceRule.task_template_id == task_id, RecurrenceRule.status == RecurrenceStatus.ACTIVE))
    if existing is not None:
        return existing
    next_run = datetime.now(timezone.utc)
    row = RecurrenceRule(workspace_id=workspace_id, task_template_id=task_id, rule=normalized, status=RecurrenceStatus.ACTIVE, next_run_at=next_run, created_by=actor_user_id)
    session.add(row)
    session.flush()
    request_id = request_id or row.id
    task = session.get(Task, task_id)
    if task is not None:
        service = TaskService(session)
        snapshot = service.snapshot(task)
        cursor = service._cursor(workspace_id, task, ChangeAction.UPDATED, request_id)
        service._operation(workspace_id, actor_user_id, request_id, task, OperationType.UPDATED, snapshot, snapshot, cursor)
    return row


def next_occurrence(rule: RecurrenceRule, current: datetime) -> datetime:
    kind = rule.rule.split(":", 1)[0]
    if kind == "DAILY":
        return current + timedelta(days=1)
    if kind == "WEEKLY":
        return current + timedelta(days=7)
    month = current.month % 12 + 1
    year = current.year + (1 if current.month == 12 else 0)
    day = min(current.day, 28)
    return current.replace(year=year, month=month, day=day)
