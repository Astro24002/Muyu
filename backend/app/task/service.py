from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.activity.models import ActivityEvent
from app.activity.repository import ActivityRepository
from app.task.models import DelayRecord, Task, TaskAssignee, TaskHandlerHistory, TaskStatusHistory
from app.task.repository import TaskRepository
from app.user.models import User


UNSET = object()
DELAY_REASONS = frozenset(
    {
        "NO_TIME",
        "TOO_LARGE",
        "NOT_WILLING",
        "FORGOT",
        "WAITING_PARTNER",
        "INTERRUPTED",
        "OTHER",
    }
)


@dataclass(frozen=True)
class TaskCreate:
    title: str
    description: str = ""
    assignee_ids: tuple[UUID, ...] = ()
    current_handler_id: UUID | None = None
    parent_task_id: UUID | None = None
    planned_start_at: datetime | None = None
    due_at: datetime | None = None
    estimated_minutes: int | None = None


@dataclass(frozen=True)
class TaskPatch:
    title: str | object = UNSET
    description: str | object = UNSET
    assignee_ids: tuple[UUID, ...] | object = UNSET
    planned_start_at: datetime | None | object = UNSET
    due_at: datetime | None | object = UNSET
    estimated_minutes: int | None | object = UNSET


class TaskNotFoundError(Exception):
    pass


class TaskRuleError(Exception):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


class TaskService:
    def __init__(self, session: Session, *, clock=lambda: datetime.now(timezone.utc)) -> None:
        self.session = session
        self.clock = clock
        self.tasks = TaskRepository(session)
        self.activity = ActivityRepository(session)

    def create(self, actor_user_id: UUID, payload: TaskCreate, *, request_id: str | None = None) -> Task:
        title = payload.title.strip()
        if not 1 <= len(title) <= 200:
            raise TaskRuleError("INVALID_TITLE", "title must contain 1 to 200 characters")
        if len(payload.description) > 5000:
            raise TaskRuleError("INVALID_DESCRIPTION", "description must contain at most 5000 characters")
        assignee_ids = self._validate_assignees(payload.assignee_ids)
        handler_id = payload.current_handler_id or actor_user_id
        if handler_id not in assignee_ids:
            raise TaskRuleError("HANDLER_NOT_ASSIGNEE", "current handler must be an assignee")
        parent = None
        if payload.parent_task_id is not None:
            parent = self._get(payload.parent_task_id)
            if parent.parent_task_id is not None:
                raise TaskRuleError("SUBTASK_DEPTH_EXCEEDED", "only one subtask level is supported")
        self._validate_estimated_minutes(payload.estimated_minutes)
        now = self.clock()
        task = Task(
            parent_task_id=parent.id if parent else None,
            title=title,
            description=payload.description,
            status="TODO",
            current_handler_id=handler_id,
            planned_start_at=payload.planned_start_at,
            due_at=payload.due_at,
            estimated_minutes=payload.estimated_minutes,
            created_by=actor_user_id,
            version=1,
            status_version=1,
            created_at=now,
            updated_at=now,
        )
        self.session.add(task)
        self.session.flush()
        for user_id in assignee_ids:
            self.session.add(TaskAssignee(task_id=task.id, user_id=user_id))
            self.tasks.set_position(user_id, task.id, self.tasks.next_position(user_id), now)
        self.session.add(
            TaskStatusHistory(
                task_id=task.id,
                from_status=None,
                to_status=task.status,
                changed_by=actor_user_id,
                changed_at=now,
            )
        )
        self.session.add(
            TaskHandlerHistory(
                task_id=task.id,
                from_user_id=None,
                to_user_id=handler_id,
                changed_by=actor_user_id,
                changed_at=now,
            )
        )
        self.session.flush()
        self._add_event(actor_user_id, task, "TASK_CREATED", None, self._snapshot(task), request_id=request_id)
        self.session.commit()
        return self._get(task.id)

    def list_tasks(self, user_id: UUID, *, parent_task_id: UUID | None = None) -> list[Task]:
        return self.tasks.list_tasks(user_id, parent_task_id=parent_task_id)

    def get(self, task_id: UUID) -> Task:
        return self._get(task_id)

    def update(self, task_id: UUID, actor_user_id: UUID, payload: TaskPatch, *, request_id: str | None = None) -> Task:
        task = self._get(task_id)
        before = self._snapshot(task)
        changed: dict[str, Any] = {}
        if payload.title is not UNSET:
            title = str(payload.title).strip()
            if not 1 <= len(title) <= 200:
                raise TaskRuleError("INVALID_TITLE", "title must contain 1 to 200 characters")
            task.title = title
            changed["title"] = title
        if payload.description is not UNSET:
            description = str(payload.description)
            if len(description) > 5000:
                raise TaskRuleError("INVALID_DESCRIPTION", "description must contain at most 5000 characters")
            task.description = description
            changed["description"] = description
        for field in ("planned_start_at", "due_at", "estimated_minutes"):
            value = getattr(payload, field)
            if value is not UNSET:
                if field == "estimated_minutes":
                    self._validate_estimated_minutes(value)
                if field == "due_at" and task.due_at is not None and value is not None:
                    if value.tzinfo is None or value.utcoffset() is None:
                        raise TaskRuleError("INVALID_DUE_TIME", "due date must include a timezone")
                    value = value.astimezone(timezone.utc)
                    if value > task.due_at:
                        raise TaskRuleError(
                            "USE_DELAY_ACTION",
                            "move an existing due date later through the delay action",
                        )
                setattr(task, field, value)
                changed[field] = value.isoformat() if isinstance(value, datetime) else value
        if payload.assignee_ids is not UNSET:
            assignee_ids = self._validate_assignees(payload.assignee_ids)
            if task.current_handler_id not in assignee_ids:
                raise TaskRuleError("HANDLER_NOT_ASSIGNEE", "current handler must be an assignee")
            current_ids = self.tasks.assignee_ids(task.id)
            for user_id in current_ids - assignee_ids:
                self.session.delete(self.session.get(TaskAssignee, (task.id, user_id)))
                self.tasks.remove_position(user_id, task.id)
            for user_id in assignee_ids - current_ids:
                self.session.add(TaskAssignee(task_id=task.id, user_id=user_id))
                self.tasks.set_position(user_id, task.id, self.tasks.next_position(user_id), self.clock())
            changed["assignee_ids"] = [str(value) for value in sorted(assignee_ids, key=str)]
        if not changed:
            raise TaskRuleError("NO_CHANGES", "at least one mutable task field is required")
        now = self.clock()
        task.version += 1
        task.updated_at = now
        self.session.flush()
        self._add_event(actor_user_id, task, "TASK_UPDATED", before, self._snapshot(task), payload=changed, request_id=request_id)
        self.session.commit()
        return self._get(task.id)

    def delete(self, task_id: UUID, actor_user_id: UUID, *, request_id: str | None = None) -> None:
        task = self._get(task_id)
        if self.tasks.active_children(task.id):
            raise TaskRuleError("TASK_HAS_SUBTASKS", "cannot delete a task with active subtasks")
        before = self._snapshot(task)
        now = self.clock()
        task.deleted_at = now
        task.updated_at = now
        task.version += 1
        self.session.flush()
        self._add_event(actor_user_id, task, "TASK_DELETED", before, self._snapshot(task), request_id=request_id)
        self.session.commit()

    def start(self, task_id: UUID, actor_user_id: UUID, *, request_id: str | None = None) -> Task:
        return self._change_status(task_id, actor_user_id, "IN_PROGRESS", "TASK_STARTED", request_id=request_id)

    def complete(self, task_id: UUID, actor_user_id: UUID, *, request_id: str | None = None) -> Task:
        return self._change_status(task_id, actor_user_id, "DONE", "TASK_COMPLETED", request_id=request_id)

    def cancel(self, task_id: UUID, actor_user_id: UUID, *, request_id: str | None = None) -> Task:
        return self._change_status(task_id, actor_user_id, "CANCELLED", "TASK_CANCELLED", request_id=request_id)

    def reopen(self, task_id: UUID, actor_user_id: UUID, *, request_id: str | None = None) -> Task:
        return self._change_status(task_id, actor_user_id, "TODO", "TASK_REOPENED", request_id=request_id)

    def transfer(
        self, task_id: UUID, actor_user_id: UUID, new_handler_id: UUID, *, request_id: str | None = None
    ) -> Task:
        task = self._get(task_id)
        if new_handler_id not in self.tasks.assignee_ids(task.id):
            raise TaskRuleError("HANDLER_NOT_ASSIGNEE", "current handler must be an assignee")
        if new_handler_id == task.current_handler_id:
            raise TaskRuleError("HANDLER_UNCHANGED", "current handler is already selected")
        before = self._snapshot(task)
        previous = task.current_handler_id
        now = self.clock()
        task.current_handler_id = new_handler_id
        task.version += 1
        task.updated_at = now
        self.session.add(
            TaskHandlerHistory(
                task_id=task.id,
                from_user_id=previous,
                to_user_id=new_handler_id,
                changed_by=actor_user_id,
                changed_at=now,
            )
        )
        self.session.flush()
        self._add_event(
            actor_user_id,
            task,
            "TASK_HANDLER_CHANGED",
            before,
            self._snapshot(task),
            payload={"from_user_id": str(previous), "to_user_id": str(new_handler_id)},
            request_id=request_id,
        )
        self.session.commit()
        return self._get(task.id)

    def delay(
        self,
        task_id: UUID,
        actor_user_id: UUID,
        *,
        new_due_at: datetime,
        reason: str,
        note: str | None,
        request_id: str | None = None,
    ) -> Task:
        task = self._get(task_id)
        if task.due_at is None:
            raise TaskRuleError("DUE_AT_REQUIRED", "a task must have a due date before it can be delayed")
        if reason not in DELAY_REASONS:
            raise TaskRuleError("INVALID_DELAY_REASON", "delay reason is not supported")
        normalized_note = note.strip() if note is not None else None
        if reason == "OTHER" and not normalized_note:
            raise TaskRuleError("DELAY_NOTE_REQUIRED", "a note is required for the OTHER delay reason")
        if normalized_note is not None and len(normalized_note) > 2000:
            raise TaskRuleError("INVALID_DELAY_NOTE", "delay note must contain at most 2000 characters")
        if new_due_at.tzinfo is None or new_due_at.utcoffset() is None:
            raise TaskRuleError("INVALID_DELAY_TIME", "new due date must include a timezone")
        new_due_at = new_due_at.astimezone(timezone.utc)
        duration_seconds = (new_due_at - task.due_at).total_seconds()
        if duration_seconds < 60:
            raise TaskRuleError("INVALID_DELAY_TIME", "new due date must be at least one minute later")

        before = self._snapshot(task)
        original_due_at = task.due_at
        now = self.clock()
        duration_minutes = int(duration_seconds // 60)
        record = DelayRecord(
            task_id=task.id,
            user_id=actor_user_id,
            original_due_at=original_due_at,
            new_due_at=new_due_at,
            delayed_at=now,
            delay_duration_minutes=duration_minutes,
            reason=reason,
            note=normalized_note,
            created_at=now,
        )
        self.session.add(record)
        task.due_at = new_due_at
        task.version += 1
        task.updated_at = now
        self.session.flush()
        self._add_event(
            actor_user_id,
            task,
            "TASK_DELAYED",
            before,
            self._snapshot(task),
            payload={
                "delay_record_id": str(record.id),
                "original_due_at": original_due_at.isoformat(),
                "new_due_at": new_due_at.isoformat(),
                "delay_duration_minutes": duration_minutes,
                "reason": reason,
                "note": normalized_note,
            },
            request_id=request_id,
        )
        self.session.commit()
        return self._get(task.id)

    def list_delays(self, task_id: UUID) -> list[DelayRecord]:
        self._get(task_id)
        return self.tasks.list_delays(task_id)

    def delay_summary(self, task_id: UUID) -> tuple[int, int]:
        self._get(task_id)
        return self.tasks.delay_count(task_id), self.tasks.total_delay_minutes(task_id)

    def block(
        self,
        task_id: UUID,
        actor_user_id: UUID,
        *,
        blocked_reason: str,
        resume_handler_id: UUID,
        waiting_for_user_id: UUID | None = None,
        request_id: str | None = None,
    ) -> Task:
        task = self._get(task_id)
        if task.status not in {"TODO", "IN_PROGRESS"}:
            raise TaskRuleError("INVALID_TASK_TRANSITION", f"cannot change {task.status} to WAITING")
        normalized_reason = blocked_reason.strip()
        if not 1 <= len(normalized_reason) <= 2000:
            raise TaskRuleError("INVALID_BLOCK_REASON", "blocked reason must contain 1 to 2000 characters")
        if resume_handler_id not in self.tasks.assignee_ids(task.id):
            raise TaskRuleError("INVALID_RESUME_HANDLER", "resume handler must be an assignee")
        if waiting_for_user_id is not None and self.session.get(User, waiting_for_user_id) is None:
            raise TaskRuleError("INVALID_WAITING_USER", "waiting user must be a fixed user")

        before = self._snapshot(task)
        previous = task.status
        now = self.clock()
        task.status = "WAITING"
        task.blocked_reason = normalized_reason
        task.blocked_since = now
        task.resume_handler_id = resume_handler_id
        task.waiting_for_user_id = waiting_for_user_id
        task.version += 1
        task.status_version += 1
        task.updated_at = now
        self.session.add(
            TaskStatusHistory(
                task_id=task.id,
                from_status=previous,
                to_status="WAITING",
                changed_by=actor_user_id,
                changed_at=now,
            )
        )
        self.session.flush()
        self._add_event(
            actor_user_id,
            task,
            "TASK_BLOCKED",
            before,
            self._snapshot(task),
            payload={
                "blocked_reason": normalized_reason,
                "resume_handler_id": str(resume_handler_id),
                "waiting_for_user_id": str(waiting_for_user_id) if waiting_for_user_id else None,
            },
            request_id=request_id,
        )
        self.session.commit()
        return self._get(task.id)

    def unblock(
        self, task_id: UUID, actor_user_id: UUID, *, request_id: str | None = None
    ) -> Task:
        task = self._get(task_id)
        if task.status != "WAITING":
            raise TaskRuleError("INVALID_TASK_TRANSITION", f"cannot unblock {task.status}")
        resume_handler_id = task.resume_handler_id
        if resume_handler_id is None or resume_handler_id not in self.tasks.assignee_ids(task.id):
            raise TaskRuleError("INVALID_RESUME_HANDLER", "resume handler must be an assignee")

        before = self._snapshot(task)
        previous_handler_id = task.current_handler_id
        now = self.clock()
        task.status = "IN_PROGRESS"
        task.current_handler_id = resume_handler_id
        self._clear_blocking_fields(task)
        task.version += 1
        task.status_version += 1
        task.updated_at = now
        self.session.add(
            TaskStatusHistory(
                task_id=task.id,
                from_status="WAITING",
                to_status="IN_PROGRESS",
                changed_by=actor_user_id,
                changed_at=now,
            )
        )
        if previous_handler_id != resume_handler_id:
            self.session.add(
                TaskHandlerHistory(
                    task_id=task.id,
                    from_user_id=previous_handler_id,
                    to_user_id=resume_handler_id,
                    changed_by=actor_user_id,
                    changed_at=now,
                )
            )
        self.session.flush()
        self._add_event(
            actor_user_id,
            task,
            "TASK_UNBLOCKED",
            before,
            self._snapshot(task),
            payload={
                "from_user_id": str(previous_handler_id),
                "to_user_id": str(resume_handler_id),
            },
            request_id=request_id,
        )
        self.session.commit()
        return self._get(task.id)

    def list_events(self, task_id: UUID) -> list[ActivityEvent]:
        self._get(task_id)
        return self.activity.list_for_target("TASK", task_id)

    def get_order(self, user_id: UUID) -> list[UUID]:
        return [task.id for task in self.list_tasks(user_id)]

    def replace_order(self, user_id: UUID, task_ids: list[UUID]) -> list[UUID]:
        if len(task_ids) != len(set(task_ids)):
            raise TaskRuleError("DUPLICATE_TASK_ORDER", "task order contains duplicates")
        visible = {task.id for task in self.tasks.list_tasks(user_id)}
        if set(task_ids) != visible:
            raise TaskRuleError("INVALID_TASK_ORDER", "task order must contain all visible tasks")
        now = self.clock()
        for position, task_id in enumerate(task_ids):
            self.tasks.set_position(user_id, task_id, position, now)
        self.session.commit()
        return task_ids

    def _change_status(
        self, task_id: UUID, actor_user_id: UUID, target_status: str, action: str, *, request_id: str | None
    ) -> Task:
        task = self._get(task_id)
        allowed = {
            "IN_PROGRESS": {"TODO"},
            "DONE": {"TODO", "IN_PROGRESS", "WAITING"},
            "CANCELLED": {"TODO", "IN_PROGRESS", "WAITING"},
            "TODO": {"DONE", "CANCELLED"},
        }
        if task.status not in allowed[target_status]:
            raise TaskRuleError("INVALID_TASK_TRANSITION", f"cannot change {task.status} to {target_status}")
        before = self._snapshot(task)
        previous = task.status
        now = self.clock()
        task.status = target_status
        task.completed_at = now if target_status == "DONE" else None
        if previous == "WAITING":
            self._clear_blocking_fields(task)
        task.version += 1
        task.status_version += 1
        task.updated_at = now
        self.session.add(
            TaskStatusHistory(
                task_id=task.id,
                from_status=previous,
                to_status=target_status,
                changed_by=actor_user_id,
                changed_at=now,
            )
        )
        self.session.flush()
        self._add_event(actor_user_id, task, action, before, self._snapshot(task), request_id=request_id)
        self.session.commit()
        return self._get(task.id)

    @staticmethod
    def _clear_blocking_fields(task: Task) -> None:
        task.blocked_reason = None
        task.blocked_since = None
        task.resume_handler_id = None
        task.waiting_for_user_id = None

    def _get(self, task_id: UUID) -> Task:
        task = self.tasks.get(task_id)
        if task is None:
            raise TaskNotFoundError(f"task {task_id} was not found")
        return task

    def _validate_assignees(self, assignee_ids: tuple[UUID, ...]) -> set[UUID]:
        unique = set(assignee_ids)
        if len(unique) != len(assignee_ids) or not 1 <= len(unique) <= 2:
            raise TaskRuleError("INVALID_ASSIGNEES", "a task must have one or two unique assignees")
        existing = set(self.session.scalars(select(User.id).where(User.id.in_(unique))))
        if existing != unique:
            raise TaskRuleError("INVALID_ASSIGNEES", "assignees must be fixed users")
        return unique

    @staticmethod
    def _validate_estimated_minutes(value: int | None) -> None:
        if value is not None and value <= 0:
            raise TaskRuleError("INVALID_ESTIMATE", "estimated minutes must be positive")

    def _add_event(
        self,
        actor_user_id: UUID,
        task: Task,
        action: str,
        before: dict | None,
        after: dict | None,
        *,
        payload: dict | None = None,
        request_id: str | None = None,
    ) -> None:
        self.session.add(
            ActivityEvent(
                actor_user_id=actor_user_id,
                target_type="TASK",
                target_id=task.id,
                action=action,
                before_json=before,
                after_json=after,
                payload_json=payload or {},
                aggregate_version=task.version,
                request_id=request_id,
                created_at=self.clock(),
            )
        )

    @staticmethod
    def _snapshot(task: Task) -> dict:
        def value(item):
            return item.isoformat() if isinstance(item, datetime) else str(item) if isinstance(item, UUID) else item

        return {
            "id": str(task.id),
            "parent_task_id": value(task.parent_task_id) if task.parent_task_id else None,
            "title": task.title,
            "description": task.description,
            "status": task.status,
            "current_handler_id": value(task.current_handler_id),
            "blocked_reason": task.blocked_reason,
            "blocked_since": value(task.blocked_since) if task.blocked_since else None,
            "resume_handler_id": value(task.resume_handler_id) if task.resume_handler_id else None,
            "waiting_for_user_id": value(task.waiting_for_user_id) if task.waiting_for_user_id else None,
            "planned_start_at": value(task.planned_start_at) if task.planned_start_at else None,
            "due_at": value(task.due_at) if task.due_at else None,
            "estimated_minutes": task.estimated_minutes,
            "completed_at": value(task.completed_at) if task.completed_at else None,
            "created_by": value(task.created_by),
            "version": task.version,
            "status_version": task.status_version,
            "deleted_at": value(task.deleted_at) if task.deleted_at else None,
            "assignee_ids": [str(item.user_id) for item in task.assignees],
        }
