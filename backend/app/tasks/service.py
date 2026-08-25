from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Any, Callable
from uuid import UUID, uuid4

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.enums import ChangeAction, ConflictStatus, OperationType, Resolution, TaskStatus
from app.db.models import (
    Task,
    TaskComment,
    TaskConflict,
    TaskOperation,
    TaskStatusHistory,
    WorkspaceChangeLog,
)
from app.db.repositories.base import Repository
from app.tasks.conflicts import TaskConflictError
from app.tasks.operations import request_fingerprint


MUTABLE_FIELDS = {"title", "description", "due_at", "planned_start_at", "estimated_minutes", "current_handler_id"}


class TaskService:
    def __init__(self, session: Session, *, now: Callable[[], datetime] = lambda: datetime.now(timezone.utc)) -> None:
        self.session = session
        self.now = now
        self.last_cursor: int | None = None

    def create(self, workspace_id: UUID, actor_user_id: UUID, request_id: UUID, title: str, description: str = "", due_at: datetime | None = None) -> Task:
        fingerprint = request_fingerprint(
            "/api/v1/tasks",
            {"title": title, "description": description, "due_at": due_at.isoformat() if due_at else None},
        )
        existing = self._existing_operation(workspace_id, actor_user_id, request_id)
        if existing is not None:
            if existing.base_versions != {"fingerprint": fingerprint}:
                raise TaskConflictError("idempotency_key_reused", "request id was used with a different payload")
            existing_task = self.session.get(Task, existing.task_id)
            if existing_task is None:
                raise TaskConflictError("not_found", "task not found")
            self.last_cursor = existing.cursor
            return existing_task
        task = Task(
            workspace_id=workspace_id,
            title=title,
            description=description,
            due_at=due_at,
            status=TaskStatus.TODO,
            created_by=actor_user_id,
            field_versions={"title": 1, "description": 1, "due_at": 1},
        )
        self.session.add(task)
        self.session.flush()
        cursor = self._cursor(workspace_id, task, ChangeAction.CREATED, request_id)
        self._operation(
            workspace_id,
            actor_user_id,
            request_id,
            task,
            OperationType.CREATED,
            None,
            self.snapshot(task),
            cursor,
            base_versions={"fingerprint": fingerprint},
        )
        return task

    def patch(self, workspace_id: UUID, actor_user_id: UUID, task_id: UUID, request_id: UUID, changes: dict[str, Any], base_field_versions: dict[str, int]) -> Task:
        task = self._task(workspace_id, task_id)
        existing = self._existing_operation(workspace_id, actor_user_id, request_id)
        fingerprint = request_fingerprint(f"/api/v1/tasks/{task_id}", {"changes": changes, "base_field_versions": base_field_versions})
        if existing is not None:
            if existing.base_versions != {"fingerprint": fingerprint}:
                raise TaskConflictError("idempotency_key_reused", "request id was used with a different payload")
            return task
        if task.deleted_at is not None:
            raise TaskConflictError("lifecycle_conflict", "deleted task must be restored before editing")
        unknown = set(changes) - MUTABLE_FIELDS
        if unknown:
            raise TaskConflictError("invalid_request", f"unknown task fields: {sorted(unknown)}")
        current_versions = dict(task.field_versions or {})
        conflicts: list[TaskConflict] = []
        before = self.snapshot(task)
        for field, value in changes.items():
            if field not in base_field_versions:
                raise TaskConflictError("invalid_request", f"missing base version for {field}")
            base = base_field_versions[field]
            current = int(current_versions.get(field, 1))
            if base != current:
                conflict = TaskConflict(
                    workspace_id=workspace_id,
                    task_id=task.id,
                    target=field,
                    base_value=before.get(field),
                    current_value=getattr(task, field),
                    proposed_value=value,
                    base_version=base,
                    current_version=current,
                    request_id=request_id,
                    status=ConflictStatus.OPEN,
                )
                self.session.add(conflict)
                conflicts.append(conflict)
        if conflicts:
            self.session.flush()
            cursor = self._cursor(workspace_id, task, ChangeAction.UPDATED, request_id)
            self._operation(
                workspace_id,
                actor_user_id,
                request_id,
                task,
                OperationType.CONFLICT_CREATED,
                before,
                before,
                cursor,
                base_versions={"fingerprint": fingerprint},
            )
            raise TaskConflictError("field_conflict", "one or more task fields changed", conflicts)
        for field, value in changes.items():
            setattr(task, field, value)
            current_versions[field] = int(current_versions.get(field, 1)) + 1
        task.field_versions = current_versions
        task.version += 1
        task.updated_at = self.now()
        after = self.snapshot(task)
        cursor = self._cursor(workspace_id, task, ChangeAction.UPDATED, request_id)
        self._operation(workspace_id, actor_user_id, request_id, task, OperationType.UPDATED, before, after, cursor, base_versions={"fingerprint": fingerprint})
        return task

    def lifecycle(self, workspace_id: UUID, actor_user_id: UUID, task_id: UUID, request_id: UUID, action: str, base_lifecycle_version: int) -> Task:
        task = self._task(workspace_id, task_id)
        fingerprint = request_fingerprint(
            f"/api/v1/tasks/{task_id}/lifecycle",
            {"action": action, "base_lifecycle_version": base_lifecycle_version},
        )
        existing = self._existing_operation(workspace_id, actor_user_id, request_id)
        if existing is not None:
            if existing.base_versions != {"fingerprint": fingerprint}:
                raise TaskConflictError("idempotency_key_reused", "request id was used with a different payload")
            return task
        if task.lifecycle_version != base_lifecycle_version:
            raise TaskConflictError("lifecycle_conflict", "task lifecycle changed")
        action = action.lower()
        before = self.snapshot(task)
        if action in {"complete", "completed"}:
            target = TaskStatus.COMPLETED
        elif action in {"reopen", "open"}:
            target = TaskStatus.TODO
        elif action == "delete":
            task.deleted_at = self.now()
            target = task.status
        else:
            raise TaskConflictError("invalid_request", "unsupported lifecycle action")
        if action != "delete":
            task.status = target
            if target == TaskStatus.COMPLETED:
                task.completed_at = self.now()
            else:
                task.completed_at = None
        task.lifecycle_version += 1
        task.status_version += 1
        task.version += 1
        task.updated_at = self.now()
        after = self.snapshot(task)
        operation = OperationType.DELETED if action == "delete" else OperationType.STATUS_CHANGED
        cursor = self._cursor(workspace_id, task, ChangeAction.DELETED if action == "delete" else ChangeAction.UPDATED, request_id)
        self._operation(
            workspace_id,
            actor_user_id,
            request_id,
            task,
            operation,
            before,
            after,
            cursor,
            base_versions={"fingerprint": fingerprint},
        )
        self.session.add(TaskStatusHistory(task_id=task.id, from_status=before["status"], to_status=task.status, changed_by=actor_user_id))
        return task

    def restore(self, workspace_id: UUID, actor_user_id: UUID, task_id: UUID, request_id: UUID, base_lifecycle_version: int) -> Task:
        task = self._task(workspace_id, task_id)
        fingerprint = request_fingerprint(
            f"/api/v1/tasks/{task_id}/restore",
            {"base_lifecycle_version": base_lifecycle_version},
        )
        existing = self._existing_operation(workspace_id, actor_user_id, request_id)
        if existing is not None:
            if existing.base_versions != {"fingerprint": fingerprint}:
                raise TaskConflictError("idempotency_key_reused", "request id was used with a different payload")
            return task
        if task.lifecycle_version != base_lifecycle_version:
            raise TaskConflictError("lifecycle_conflict", "task lifecycle changed")
        if task.deleted_at is None:
            return task
        before = self.snapshot(task)
        task.deleted_at = None
        task.lifecycle_version += 1
        task.version += 1
        task.updated_at = self.now()
        after = self.snapshot(task)
        cursor = self._cursor(workspace_id, task, ChangeAction.RESTORED, request_id)
        self._operation(
            workspace_id,
            actor_user_id,
            request_id,
            task,
            OperationType.RESTORED,
            before,
            after,
            cursor,
            base_versions={"fingerprint": fingerprint},
        )
        return task

    def add_comment(self, workspace_id: UUID, actor_user_id: UUID, task_id: UUID, body: str, request_id: UUID | None = None) -> TaskComment:
        task = self._task(workspace_id, task_id)
        if task.deleted_at is not None:
            raise TaskConflictError("lifecycle_conflict", "deleted task cannot receive comments")
        request_id = request_id or uuid4()
        fingerprint = request_fingerprint(
            f"/api/v1/tasks/{task_id}/comments",
            {"body": body},
        )
        existing = self._existing_operation(workspace_id, actor_user_id, request_id)
        if existing is not None:
            if existing.base_versions != {"fingerprint": fingerprint}:
                raise TaskConflictError("idempotency_key_reused", "request id was used with a different payload")
            comment_id = (existing.after_state or {}).get("comment_id")
            comment = self.session.get(TaskComment, UUID(comment_id)) if comment_id else None
            if comment is None:
                raise TaskConflictError("not_found", "comment not found")
            return comment
        comment = TaskComment(workspace_id=workspace_id, task_id=task_id, author_user_id=actor_user_id, body=body)
        self.session.add(comment)
        self.session.flush()
        cursor = self._cursor(workspace_id, task, ChangeAction.UPDATED, request_id)
        self._operation(
            workspace_id,
            actor_user_id,
            request_id,
            task,
            OperationType.COMMENTED,
            self.snapshot(task),
            {"task": self.snapshot(task), "comment_id": str(comment.id)},
            cursor,
            base_versions={"fingerprint": fingerprint},
        )
        return comment

    def snapshot(self, task: Task) -> dict[str, Any]:
        return {
            "id": str(task.id),
            "workspace_id": str(task.workspace_id),
            "parent_task_id": str(task.parent_task_id) if task.parent_task_id else None,
            "title": task.title,
            "description": task.description,
            "due_at": task.due_at.isoformat() if task.due_at else None,
            "status": task.status.value if hasattr(task.status, "value") else task.status,
            "current_handler_id": str(task.current_handler_id) if task.current_handler_id else "",
            "blocked_reason": task.blocked_reason,
            "blocked_since": task.blocked_since.isoformat() if task.blocked_since else None,
            "resume_handler_id": str(task.resume_handler_id) if task.resume_handler_id else None,
            "waiting_for_user_id": str(task.waiting_for_user_id) if task.waiting_for_user_id else None,
            "planned_start_at": task.planned_start_at.isoformat() if task.planned_start_at else None,
            "estimated_minutes": task.estimated_minutes,
            "completed_at": task.completed_at.isoformat() if task.completed_at else None,
            "created_by": str(task.created_by),
            "created_at": task.created_at.isoformat() if task.created_at else self.now().isoformat(),
            "updated_at": task.updated_at.isoformat() if task.updated_at else self.now().isoformat(),
            "assignee_ids": [],
            "delay_count": 0,
            "total_delay_minutes": 0,
            "version": task.version,
            "field_versions": dict(task.field_versions or {}),
            "lifecycle_version": task.lifecycle_version,
            "deleted_at": task.deleted_at.isoformat() if task.deleted_at else None,
        }

    def _task(self, workspace_id: UUID, task_id: UUID) -> Task:
        task = self.session.scalar(select(Task).where(Task.id == task_id, Task.workspace_id == workspace_id).with_for_update())
        if task is None:
            raise TaskConflictError("not_found", "task not found")
        return task

    def _existing_operation(self, workspace_id: UUID, actor_user_id: UUID, request_id: UUID) -> TaskOperation | None:
        return self.session.scalar(select(TaskOperation).where(TaskOperation.workspace_id == workspace_id, TaskOperation.request_id == request_id))

    def _cursor(self, workspace_id: UUID, task: Task, action: ChangeAction, request_id: UUID) -> int:
        cursor = Repository(self.session).allocate_workspace_cursor(workspace_id)
        self.session.add(WorkspaceChangeLog(workspace_id=workspace_id, cursor=cursor, resource_type="task", resource_id=task.id, action=action, operation_id=request_id))
        self.last_cursor = cursor
        return cursor

    def _operation(self, workspace_id: UUID, actor_user_id: UUID, request_id: UUID, task: Task, operation_type: OperationType, before: dict[str, Any] | None, after: dict[str, Any] | None, cursor: int, base_versions: dict[str, Any] | None = None) -> TaskOperation:
        operation = TaskOperation(workspace_id=workspace_id, task_id=task.id, actor_user_id=actor_user_id, request_id=request_id, operation_type=operation_type, before_state=before, after_state=after, base_versions=base_versions, resulting_versions=task.field_versions, cursor=cursor)
        self.session.add(operation)
        self.session.flush()
        return operation
