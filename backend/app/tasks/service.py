from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Any, Callable
from uuid import UUID, uuid4

from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session

from app.db.enums import ChangeAction, ConflictStatus, MembershipStatus, OperationType, PUBLIC_TASK_STATUS, Resolution, TaskStatus
from app.db.models import (
    DelayRecord,
    Task,
    TaskAssignee,
    TaskComment,
    TaskConflict,
    TaskOperation,
    TaskStatusHistory,
    WorkspaceChangeLog,
    WorkspaceMembership,
)
from app.db.repositories.base import Repository
from app.tasks.conflicts import TaskConflictError
from app.tasks.operations import request_fingerprint


MUTABLE_FIELDS = {"title", "description", "due_at", "planned_start_at", "estimated_minutes", "current_handler_id", "assignee_ids"}
TRANSITIONS = {
    "TODO": {"IN_PROGRESS", "WAITING", "DONE", "CANCELLED"},
    "IN_PROGRESS": {"WAITING", "DONE", "CANCELLED"},
    "WAITING": {"IN_PROGRESS", "DONE", "CANCELLED"},
    "DONE": {"TODO"},
    "CANCELLED": {"TODO"},
}


class TaskService:
    def __init__(self, session: Session, *, now: Callable[[], datetime] = lambda: datetime.now(timezone.utc)) -> None:
        self.session = session
        self.now = now
        self.last_cursor: int | None = None

    def create(self, workspace_id: UUID, actor_user_id: UUID, request_id: UUID, title: str, description: str = "", due_at: datetime | None = None, parent_task_id: UUID | None = None, assignee_ids: list[UUID] | None = None, planned_start_at: datetime | None = None, estimated_minutes: int | None = None) -> Task:
        title = title.strip()
        if not title:
            raise TaskConflictError("invalid_request", "title is required")
        if parent_task_id is not None:
            parent = self.session.scalar(select(Task).where(Task.id == parent_task_id, Task.workspace_id == workspace_id))
            if parent is None:
                raise TaskConflictError("not_found", "parent task not found")
            if parent.parent_task_id is not None:
                raise TaskConflictError("nested_task_not_allowed", "subtasks cannot have subtasks")
        assignees = list(dict.fromkeys(assignee_ids or [actor_user_id]))
        if len(assignees) not in (1, 2):
            raise TaskConflictError("invalid_request", "assignee_ids must contain one or two users")
        if actor_user_id not in assignees:
            raise TaskConflictError("invalid_request", "current handler must be an assignee")
        members = set(self.session.scalars(select(WorkspaceMembership.user_id).where(WorkspaceMembership.workspace_id == workspace_id, WorkspaceMembership.status == MembershipStatus.ACTIVE, WorkspaceMembership.user_id.in_(assignees))).all())
        if members != set(assignees):
            raise TaskConflictError("invalid_request", "assignees must be active workspace members")
        fingerprint = request_fingerprint(
            "/api/v1/tasks",
            {"title": title, "description": description, "due_at": due_at.isoformat() if due_at else None, "parent_task_id": str(parent_task_id) if parent_task_id else None, "assignee_ids": [str(item) for item in assignees], "planned_start_at": planned_start_at.isoformat() if planned_start_at else None, "estimated_minutes": estimated_minutes},
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
            parent_task_id=parent_task_id,
            planned_start_at=planned_start_at,
            estimated_minutes=estimated_minutes,
            current_handler_id=actor_user_id,
            status=TaskStatus.TODO,
            created_by=actor_user_id,
            field_versions={"title": 1, "description": 1, "due_at": 1, "planned_start_at": 1, "estimated_minutes": 1, "current_handler_id": 1, "assignee_ids": 1},
        )
        self.session.add(task)
        self.session.flush()
        self.session.add_all([TaskAssignee(task_id=task.id, user_id=user_id) for user_id in assignees])
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
            self.last_cursor = existing.cursor
            return task
        if task.deleted_at is not None:
            raise TaskConflictError("lifecycle_conflict", "deleted task must be restored before editing")
        unknown = set(changes) - MUTABLE_FIELDS
        if unknown:
            raise TaskConflictError("invalid_request", f"unknown task fields: {sorted(unknown)}")
        if "assignee_ids" in changes:
            changes = dict(changes)
            try:
                changes["assignee_ids"] = [UUID(str(item)) for item in (changes["assignee_ids"] or [])]
            except (TypeError, ValueError) as exc:
                raise TaskConflictError("invalid_request", "invalid assignee id") from exc
        if "current_handler_id" in changes and changes["current_handler_id"] is not None:
            try:
                changes["current_handler_id"] = UUID(str(changes["current_handler_id"]))
            except (TypeError, ValueError) as exc:
                raise TaskConflictError("invalid_request", "invalid handler id") from exc
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
                    current_value=[str(item) for item in self.session.scalars(select(TaskAssignee.user_id).where(TaskAssignee.task_id == task.id)).all()] if field == "assignee_ids" else (str(getattr(task, field)) if isinstance(getattr(task, field), UUID) else getattr(task, field)),
                    proposed_value=[str(item) for item in value] if field == "assignee_ids" else (str(value) if isinstance(value, UUID) else value),
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
        if "assignee_ids" in changes:
            values = list(dict.fromkeys(changes["assignee_ids"] or []))
            if len(values) not in (1, 2):
                raise TaskConflictError("invalid_request", "assignee_ids must contain one or two users")
            members = set(self.session.scalars(select(WorkspaceMembership.user_id).where(WorkspaceMembership.workspace_id == workspace_id, WorkspaceMembership.status == MembershipStatus.ACTIVE, WorkspaceMembership.user_id.in_(values))).all())
            if members != set(values):
                raise TaskConflictError("invalid_request", "assignees must be active workspace members")
            if changes.get("current_handler_id") is not None and changes["current_handler_id"] not in values:
                raise TaskConflictError("invalid_request", "current handler must be an assignee")
            if changes.get("current_handler_id") is None and task.current_handler_id is not None and task.current_handler_id not in values:
                raise TaskConflictError("invalid_request", "current handler must be an assignee")
        elif "current_handler_id" in changes:
            handler = changes["current_handler_id"]
            existing_assignees = set(self.session.scalars(select(TaskAssignee.user_id).where(TaskAssignee.task_id == task.id)).all())
            if handler is not None and handler not in existing_assignees:
                raise TaskConflictError("invalid_request", "current handler must be an assignee")
            if handler is not None and self.session.scalar(select(WorkspaceMembership.id).where(WorkspaceMembership.workspace_id == workspace_id, WorkspaceMembership.user_id == handler, WorkspaceMembership.status == MembershipStatus.ACTIVE)) is None:
                raise TaskConflictError("invalid_request", "current handler must be an active workspace member")
        for field, value in changes.items():
            if field == "assignee_ids":
                self.session.execute(delete(TaskAssignee).where(TaskAssignee.task_id == task.id))
                self.session.add_all([TaskAssignee(task_id=task.id, user_id=user_id) for user_id in value])
                current_versions[field] = int(current_versions.get(field, 1)) + 1
                continue
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
        action = action.lower()
        if action == "delete":
            task = self._task(workspace_id, task_id)
            fingerprint = request_fingerprint(f"/api/v1/tasks/{task_id}/lifecycle", {"action": action, "base_lifecycle_version": base_lifecycle_version})
            existing = self._existing_operation(workspace_id, actor_user_id, request_id)
            if existing is not None:
                if existing.base_versions != {"fingerprint": fingerprint}:
                    raise TaskConflictError("idempotency_key_reused", "request id was used with a different payload")
                self.last_cursor = existing.cursor
                return task
            if task.lifecycle_version != base_lifecycle_version:
                raise TaskConflictError("lifecycle_conflict", "task lifecycle changed")
            before = self.snapshot(task)
            task.deleted_at = self.now()
            task.lifecycle_version += 1
            task.status_version += 1
            task.version += 1
            task.updated_at = self.now()
            cursor = self._cursor(workspace_id, task, ChangeAction.DELETED, request_id)
            self._operation(workspace_id, actor_user_id, request_id, task, OperationType.DELETED, before, self.snapshot(task), cursor, base_versions={"fingerprint": fingerprint})
            return task
        target = "DONE" if action in {"complete", "completed"} else "TODO" if action in {"reopen", "open"} else None
        if target is None:
            raise TaskConflictError("invalid_request", "unsupported lifecycle action")
        # The compatibility endpoint historically called its optimistic version
        # ``base_lifecycle_version``. Validate that lifecycle version first, then
        # pass the authoritative status version to the shared transition path.
        task = self._task(workspace_id, task_id)
        if task.lifecycle_version != base_lifecycle_version:
            raise TaskConflictError("lifecycle_conflict", "task lifecycle changed")
        return self.transition(workspace_id, actor_user_id, task_id, request_id, target, task.status_version)

    def transition(self, workspace_id: UUID, actor_user_id: UUID, task_id: UUID, request_id: UUID, target_status: str, base_status_version: int, blocked_reason: str | None = None, resume_handler_id: UUID | None = None, waiting_for_user_id: UUID | None = None) -> Task:
        task = self._task(workspace_id, task_id)
        target_status = str(target_status)
        if target_status not in TRANSITIONS:
            raise TaskConflictError("invalid_request", "unsupported target status")
        fingerprint = request_fingerprint(f"/api/v1/tasks/{task_id}/transition", {"target_status": target_status, "base_status_version": base_status_version, "blocked_reason": blocked_reason, "resume_handler_id": str(resume_handler_id) if resume_handler_id else None, "waiting_for_user_id": str(waiting_for_user_id) if waiting_for_user_id else None})
        existing = self._existing_operation(workspace_id, actor_user_id, request_id)
        if existing is not None:
            if existing.base_versions != {"fingerprint": fingerprint}:
                raise TaskConflictError("idempotency_key_reused", "request id was used with a different payload")
            self.last_cursor = existing.cursor
            return task
        before = self.snapshot(task)
        raw_status = task.status.value if hasattr(task.status, "value") else str(task.status)
        current_public = "DONE" if raw_status == "COMPLETED" else raw_status
        if task.status_version != base_status_version:
            conflict = TaskConflict(workspace_id=workspace_id, task_id=task.id, target="status", base_value=current_public, current_value=current_public, proposed_value=target_status, base_version=base_status_version, current_version=task.status_version, request_id=request_id, status=ConflictStatus.OPEN)
            self.session.add(conflict)
            self.session.flush()
            cursor = self._cursor(workspace_id, task, ChangeAction.UPDATED, request_id)
            self._operation(workspace_id, actor_user_id, request_id, task, OperationType.CONFLICT_CREATED, before, before, cursor, base_versions={"fingerprint": fingerprint})
            raise TaskConflictError("field_conflict", "task status changed", [conflict])
        if target_status not in TRANSITIONS[current_public]:
            raise TaskConflictError("invalid_request", f"cannot transition {current_public} to {target_status}")
        target = TaskStatus.COMPLETED if target_status == "DONE" else TaskStatus(target_status)
        task.status = target
        if target == TaskStatus.COMPLETED:
            task.completed_at = self.now()
        elif current_public == "DONE":
            task.completed_at = None
        if target_status == "WAITING":
            if not blocked_reason or resume_handler_id is None:
                raise TaskConflictError("invalid_request", "blocked_reason and resume_handler_id are required")
            resume_handler_id = self._validated_assignee_handler(workspace_id, task, resume_handler_id)
            if waiting_for_user_id is not None:
                waiting_for_user_id = self._validated_member(workspace_id, waiting_for_user_id)
            task.blocked_reason = blocked_reason
            task.blocked_since = self.now()
            task.resume_handler_id = resume_handler_id
            task.waiting_for_user_id = waiting_for_user_id
        elif current_public == "WAITING" or target_status == "IN_PROGRESS":
            task.blocked_reason = task.blocked_since = task.resume_handler_id = task.waiting_for_user_id = None
            if resume_handler_id is not None:
                task.current_handler_id = self._validated_assignee_handler(workspace_id, task, resume_handler_id)
        task.lifecycle_version += 1
        task.status_version += 1
        task.version += 1
        task.updated_at = self.now()
        after = self.snapshot(task)
        cursor = self._cursor(workspace_id, task, ChangeAction.UPDATED, request_id)
        self._operation(
            workspace_id,
            actor_user_id,
            request_id,
            task,
            OperationType.STATUS_CHANGED,
            before,
            after,
            cursor,
            base_versions={"fingerprint": fingerprint},
        )
        self.session.add(TaskStatusHistory(task_id=task.id, from_status=TaskStatus.COMPLETED if before["status"] == "DONE" else TaskStatus(before["status"]), to_status=task.status, changed_by=actor_user_id))
        return task

    def block(self, workspace_id: UUID, actor_user_id: UUID, task_id: UUID, request_id: UUID, base_status_version: int, blocked_reason: str, resume_handler_id: UUID, waiting_for_user_id: UUID | None = None) -> Task:
        return self.transition(workspace_id, actor_user_id, task_id, request_id, "WAITING", base_status_version, blocked_reason, resume_handler_id, waiting_for_user_id)

    def unblock(self, workspace_id: UUID, actor_user_id: UUID, task_id: UUID, request_id: UUID, base_status_version: int, resume_handler_id: UUID | None = None) -> Task:
        return self.transition(workspace_id, actor_user_id, task_id, request_id, "IN_PROGRESS", base_status_version, resume_handler_id=resume_handler_id)

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
        raw_status = task.status.value if hasattr(task.status, "value") else str(task.status)
        public_status = "DONE" if raw_status == "COMPLETED" else raw_status
        return {
            "id": str(task.id),
            "workspace_id": str(task.workspace_id),
            "parent_task_id": str(task.parent_task_id) if task.parent_task_id else None,
            "title": task.title,
            "description": task.description,
            "due_at": task.due_at.isoformat() if task.due_at else None,
            "status": public_status,
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
            "assignee_ids": [str(item) for item in self.session.scalars(select(TaskAssignee.user_id).where(TaskAssignee.task_id == task.id)).all()],
            "delay_count": int(self.session.scalar(select(func.count(DelayRecord.id)).where(DelayRecord.task_id == task.id)) or 0),
            "total_delay_minutes": int(self.session.scalar(select(func.coalesce(func.sum(DelayRecord.delay_duration_minutes), 0)).where(DelayRecord.task_id == task.id)) or 0),
            "version": task.version,
            "field_versions": dict(task.field_versions or {}),
            "lifecycle_version": task.lifecycle_version,
            "status_version": task.status_version,
            "deleted_at": task.deleted_at.isoformat() if task.deleted_at else None,
        }

    def _task(self, workspace_id: UUID, task_id: UUID) -> Task:
        task = self.session.scalar(select(Task).where(Task.id == task_id, Task.workspace_id == workspace_id).with_for_update())
        if task is None:
            raise TaskConflictError("not_found", "task not found")
        return task

    def _validated_member(self, workspace_id: UUID, user_id: UUID | str) -> UUID:
        try:
            normalized = UUID(str(user_id))
        except (TypeError, ValueError) as exc:
            raise TaskConflictError("invalid_request", "invalid handler id") from exc
        member = self.session.scalar(
            select(WorkspaceMembership.id).where(
                WorkspaceMembership.workspace_id == workspace_id,
                WorkspaceMembership.user_id == normalized,
                WorkspaceMembership.status == MembershipStatus.ACTIVE,
            )
        )
        if member is None:
            raise TaskConflictError("invalid_request", "handler must be an active workspace member")
        return normalized

    def _validated_assignee_handler(self, workspace_id: UUID, task: Task, user_id: UUID | str) -> UUID:
        normalized = self._validated_member(workspace_id, user_id)
        assigned = self.session.scalar(
            select(TaskAssignee.user_id).where(
                TaskAssignee.task_id == task.id,
                TaskAssignee.user_id == normalized,
            )
        )
        if assigned is None:
            raise TaskConflictError("invalid_request", "handler must be a task assignee")
        return normalized

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
