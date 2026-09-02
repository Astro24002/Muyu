from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Any, Callable
from uuid import UUID, uuid4

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.db.enums import ChangeAction, ConflictStatus, MembershipStatus, OperationType, PUBLIC_TASK_STATUS, Resolution, TaskQuadrant, TaskStatus
from app.db.models import (
    DelayRecord,
    ActivityEvent,
    Task,
    TaskComment,
    TaskConflict,
    TaskHandlerHistory,
    TaskOperation,
    TaskStatusHistory,
    WorkspaceChangeLog,
    WorkspaceMembership,
)
from app.db.repositories.base import Repository
from app.tasks.conflicts import TaskConflictError
from app.tasks.operations import request_fingerprint
from app.tasks.numbering import TaskNumberAllocator


MUTABLE_FIELDS = {"title", "description", "due_at", "planned_start_at", "estimated_minutes", "current_handler_id", "quadrant", "progress", "labels"}
ALLOWED_PROGRESS = {20, 40, 60, 80}
MAX_TASK_LABELS = 10
MAX_TASK_LABEL_LENGTH = 32
MAX_TASK_LABEL_CHARS = 320
TRANSITIONS = {
    "TODO": {"IN_PROGRESS", "WAITING", "DONE", "CANCELLED"},
    "IN_PROGRESS": {"WAITING", "DONE", "CANCELLED"},
    "WAITING": {"IN_PROGRESS", "DONE", "CANCELLED"},
    "DONE": {"TODO"},
    "CANCELLED": {"TODO"},
}


def normalize_task_labels(value: object) -> list[str]:
    """Normalize and validate the small, task-local classification set."""
    if not isinstance(value, (list, tuple)):
        raise TaskConflictError("invalid_request", "labels must be an array")
    labels: list[str] = []
    seen: set[str] = set()
    total_chars = 0
    for raw in value:
        if not isinstance(raw, str):
            raise TaskConflictError("invalid_request", "labels must contain strings")
        label = raw.strip()
        if not label:
            raise TaskConflictError("invalid_request", "labels cannot contain empty values")
        if len(label) > MAX_TASK_LABEL_LENGTH:
            raise TaskConflictError(
                "invalid_request",
                f"each label must be at most {MAX_TASK_LABEL_LENGTH} characters",
            )
        key = label.casefold()
        if key in seen:
            continue
        seen.add(key)
        labels.append(label)
        total_chars += len(label)
        if len(labels) > MAX_TASK_LABELS:
            raise TaskConflictError(
                "invalid_request",
                f"a task can have at most {MAX_TASK_LABELS} labels",
            )
        if total_chars > MAX_TASK_LABEL_CHARS:
            raise TaskConflictError(
                "invalid_request",
                f"labels can contain at most {MAX_TASK_LABEL_CHARS} characters",
            )
    return labels


class TaskService:
    def __init__(self, session: Session, *, now: Callable[[], datetime] = lambda: datetime.now(timezone.utc)) -> None:
        self.session = session
        self.now = now
        self.last_cursor: int | None = None

    def create(self, workspace_id: UUID, actor_user_id: UUID, request_id: UUID, title: str, description: str = "", due_at: datetime | None = None, parent_task_id: UUID | None = None, planned_start_at: datetime | None = None, estimated_minutes: int | None = None, quadrant: str | None = None, labels: list[str] | None = None) -> Task:
        title = title.strip()
        if not title:
            raise TaskConflictError("invalid_request", "title is required")
        if quadrant not in {item.value for item in TaskQuadrant}:
            raise TaskConflictError("invalid_request", "quadrant must be Q1, Q2, Q3, or Q4")
        self._validated_member(workspace_id, actor_user_id)
        normalized_labels = normalize_task_labels([] if labels is None else labels)
        if parent_task_id is not None:
            parent = self.session.scalar(select(Task).where(Task.id == parent_task_id, Task.workspace_id == workspace_id))
            if parent is None:
                raise TaskConflictError("not_found", "parent task not found")
            if parent.parent_task_id is not None:
                raise TaskConflictError("nested_task_not_allowed", "subtasks cannot have subtasks")
        fingerprint = request_fingerprint(
            "/api/v1/tasks",
            {"title": title, "description": description, "due_at": due_at.isoformat() if due_at else None, "parent_task_id": str(parent_task_id) if parent_task_id else None, "planned_start_at": planned_start_at.isoformat() if planned_start_at else None, "estimated_minutes": estimated_minutes, "quadrant": quadrant, "labels": normalized_labels},
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
            task_number=TaskNumberAllocator().allocate(self.session, self.now()),
            title=title,
            description=description,
            due_at=due_at,
            parent_task_id=parent_task_id,
            planned_start_at=planned_start_at,
            estimated_minutes=estimated_minutes,
            quadrant=TaskQuadrant(quadrant),
            labels=normalized_labels,
            current_handler_id=actor_user_id,
            status=TaskStatus.TODO,
            created_by=actor_user_id,
            field_versions={"title": 1, "description": 1, "due_at": 1, "planned_start_at": 1, "estimated_minutes": 1, "current_handler_id": 1, "quadrant": 1, "progress": 1, "labels": 1},
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
        changes = dict(changes)
        existing = self._existing_operation(workspace_id, actor_user_id, request_id)
        unknown = set(changes) - MUTABLE_FIELDS
        if unknown:
            raise TaskConflictError("invalid_request", f"unknown task fields: {sorted(unknown)}")
        if "current_handler_id" in changes:
            try:
                changes["current_handler_id"] = UUID(str(changes["current_handler_id"]))
            except (TypeError, ValueError) as exc:
                raise TaskConflictError("invalid_request", "invalid handler id") from exc
        if "quadrant" in changes:
            quadrant = changes["quadrant"]
            if quadrant not in {item.value for item in TaskQuadrant}:
                raise TaskConflictError("invalid_request", "quadrant must be Q1, Q2, Q3, or Q4")
            changes = dict(changes)
            changes["quadrant"] = TaskQuadrant(quadrant)
        if "labels" in changes:
            changes = dict(changes)
            changes["labels"] = normalize_task_labels(changes["labels"])
        if "progress" in changes:
            progress = changes["progress"]
            if progress is not None and progress not in ALLOWED_PROGRESS:
                raise TaskConflictError("invalid_request", "progress must be 20, 40, 60, or 80")
            if task.status != TaskStatus.IN_PROGRESS:
                raise TaskConflictError("invalid_request", "progress can only be changed while task is in progress")
        fingerprint = request_fingerprint(
            f"/api/v1/tasks/{task_id}",
            {"changes": changes, "base_field_versions": base_field_versions},
        )
        if existing is not None:
            if existing.base_versions != {"fingerprint": fingerprint}:
                raise TaskConflictError("idempotency_key_reused", "request id was used with a different payload")
            self.last_cursor = existing.cursor
            return task
        if "current_handler_id" in changes:
            self._validated_member(workspace_id, changes["current_handler_id"])
        self._require_handler(task, actor_user_id)
        if task.deleted_at is not None:
            raise TaskConflictError("lifecycle_conflict", "deleted task must be restored before editing")
        current_versions = dict(task.field_versions or {})
        current_versions.pop("assignee_ids", None)
        conflicts: list[TaskConflict] = []
        before = self.snapshot(task)
        previous_handler_id = task.current_handler_id
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
                    current_value=str(getattr(task, field)) if isinstance(getattr(task, field), UUID) else getattr(task, field).value if isinstance(getattr(task, field), TaskQuadrant) else getattr(task, field),
                    proposed_value=str(value) if isinstance(value, UUID) else value.value if isinstance(value, TaskQuadrant) else value,
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
        self._record_handler_change(task, previous_handler_id, actor_user_id)
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
            self._require_handler(task, actor_user_id)
            live_child = self.session.scalar(
                select(Task.id).where(
                    Task.workspace_id == workspace_id,
                    Task.parent_task_id == task.id,
                    Task.deleted_at.is_(None),
                )
            )
            if live_child is not None:
                raise TaskConflictError("lifecycle_conflict", "parent task has live children")
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
        task = self._task(workspace_id, task_id)
        fingerprint = request_fingerprint(
            f"/api/v1/tasks/{task_id}/lifecycle",
            {"action": action, "base_lifecycle_version": base_lifecycle_version},
        )
        existing = self._existing_operation(workspace_id, actor_user_id, request_id)
        if existing is not None:
            if existing.base_versions != {"fingerprint": fingerprint}:
                raise TaskConflictError("idempotency_key_reused", "request id was used with a different payload")
            self.last_cursor = existing.cursor
            return task
        self._require_handler(task, actor_user_id)
        if task.lifecycle_version != base_lifecycle_version:
            raise TaskConflictError("lifecycle_conflict", "task lifecycle changed")
        return self.transition(workspace_id, actor_user_id, task_id, request_id, target, task.status_version, operation_fingerprint=fingerprint)

    def transition(self, workspace_id: UUID, actor_user_id: UUID, task_id: UUID, request_id: UUID, target_status: str, base_status_version: int, blocked_reason: str | None = None, resume_handler_id: UUID | None = None, waiting_for_user_id: UUID | None = None, operation_fingerprint: str | None = None) -> Task:
        task = self._task(workspace_id, task_id)
        target_status = str(target_status)
        if target_status not in TRANSITIONS:
            raise TaskConflictError("invalid_request", "unsupported target status")
        fingerprint = operation_fingerprint or request_fingerprint(f"/api/v1/tasks/{task_id}/transition", {"target_status": target_status, "base_status_version": base_status_version, "blocked_reason": blocked_reason, "resume_handler_id": str(resume_handler_id) if resume_handler_id else None, "waiting_for_user_id": str(waiting_for_user_id) if waiting_for_user_id else None})
        existing = self._existing_operation(workspace_id, actor_user_id, request_id)
        if existing is not None:
            if existing.base_versions != {"fingerprint": fingerprint}:
                raise TaskConflictError("idempotency_key_reused", "request id was used with a different payload")
            self.last_cursor = existing.cursor
            return task
        self._require_handler(task, actor_user_id)
        if task.deleted_at is not None:
            raise TaskConflictError("lifecycle_conflict", "deleted task must be restored before status changes")
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
        previous_handler_id = task.current_handler_id
        recovery_handler_id: UUID | None = None
        if target_status == "WAITING":
            if not blocked_reason or resume_handler_id is None:
                raise TaskConflictError("invalid_request", "blocked_reason and resume_handler_id are required")
            resume_handler_id = self._validated_member(workspace_id, resume_handler_id)
            if waiting_for_user_id is not None:
                waiting_for_user_id = self._validated_member(workspace_id, waiting_for_user_id)
        elif target_status == "IN_PROGRESS":
            if current_public == "WAITING":
                recovery_handler_id = resume_handler_id or task.resume_handler_id
                if recovery_handler_id is None:
                    raise TaskConflictError("invalid_request", "waiting task has no active resume handler")
                recovery_handler_id = self._validated_member(workspace_id, recovery_handler_id)
            elif resume_handler_id is not None:
                # Preserve the explicit API accepted by older unblock callers.
                recovery_handler_id = self._validated_member(workspace_id, resume_handler_id)

        task.status = target
        if target == TaskStatus.COMPLETED:
            task.completed_at = self.now()
        elif current_public == "DONE":
            task.completed_at = None
        if target_status == "WAITING":
            task.blocked_reason = blocked_reason
            task.blocked_since = self.now()
            task.resume_handler_id = resume_handler_id
            task.waiting_for_user_id = waiting_for_user_id
        elif current_public == "WAITING" or target_status == "IN_PROGRESS":
            task.blocked_reason = task.blocked_since = task.resume_handler_id = task.waiting_for_user_id = None
            if recovery_handler_id is not None:
                task.current_handler_id = recovery_handler_id
            if target_status == "IN_PROGRESS" and task.progress is None:
                task.progress = 20
                versions = dict(task.field_versions or {})
                versions["progress"] = int(versions.get("progress", 1)) + 1
                task.field_versions = versions
        self._record_handler_change(task, previous_handler_id, actor_user_id)
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
            self.last_cursor = existing.cursor
            return task
        self._require_handler(task, actor_user_id)
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

    def resolve_conflict(self, workspace_id: UUID, actor_user_id: UUID, task_id: UUID, conflict_id: UUID, request_id: UUID, resolution: str) -> Task:
        task = self.session.scalar(
            select(Task).where(Task.id == task_id, Task.workspace_id == workspace_id).with_for_update()
        )
        conflict = self.session.scalar(
            select(TaskConflict).where(
                TaskConflict.id == conflict_id,
                TaskConflict.task_id == task_id,
                TaskConflict.workspace_id == workspace_id,
            ).with_for_update()
        )
        if task is None or conflict is None:
            raise TaskConflictError("not_found", "conflict not found")
        fingerprint = request_fingerprint(
            f"/api/v1/tasks/{task_id}/conflicts/{conflict_id}/resolve",
            {"resolution": resolution},
        )
        existing = self._existing_operation(workspace_id, actor_user_id, request_id)
        if existing is not None:
            if existing.base_versions != {"fingerprint": fingerprint}:
                raise TaskConflictError("idempotency_key_reused", "request id was used with a different payload")
            self.last_cursor = existing.cursor
            return task
        if task.deleted_at is not None:
            raise TaskConflictError("lifecycle_conflict", "deleted task must be restored before conflict resolution")
        if conflict.status != ConflictStatus.OPEN:
            raise TaskConflictError("lifecycle_conflict", "conflict is already resolved")
        if resolution not in {"current", "proposed"}:
            raise TaskConflictError("invalid_request", "resolution must be current or proposed")
        before = self.snapshot(task)
        if resolution == "proposed":
            versions = dict(task.field_versions or {})
            current_version = int(versions.get(conflict.target, 1))
            if current_version != conflict.current_version:
                raise TaskConflictError("field_conflict", "task field changed since conflict creation", [conflict])
            if conflict.target == "current_handler_id":
                try:
                    value = self._validated_member(workspace_id, conflict.proposed_value)
                except (TypeError, ValueError) as exc:
                    raise TaskConflictError("invalid_request", "invalid proposed handler id") from exc
                task.current_handler_id = value
            elif conflict.target not in MUTABLE_FIELDS:
                raise TaskConflictError("invalid_request", "invalid task conflict field")
            else:
                setattr(task, conflict.target, conflict.proposed_value)
            versions.pop("assignee_ids", None)
            versions[conflict.target] = current_version + 1
            task.field_versions = versions
            task.version += 1
            task.updated_at = self.now()
        conflict.status = ConflictStatus.RESOLVED
        conflict.resolution = Resolution.ACCEPT_PROPOSED if resolution == "proposed" else Resolution.KEEP_CURRENT
        conflict.resolved_by = actor_user_id
        conflict.resolved_at = self.now()
        after = self.snapshot(task)
        cursor = self._cursor(workspace_id, task, ChangeAction.UPDATED, request_id)
        self._operation(
            workspace_id,
            actor_user_id,
            request_id,
            task,
            OperationType.CONFLICT_RESOLVED,
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
        cursor = self._resource_cursor(workspace_id, "comment", comment.id, ChangeAction.CREATED, request_id)
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

    def delete_comment(self, workspace_id: UUID, actor_user_id: UUID, comment_id: UUID, request_id: UUID, base_version: int) -> TaskComment:
        comment = self.session.scalar(
            select(TaskComment)
            .where(TaskComment.id == comment_id, TaskComment.workspace_id == workspace_id)
        )
        if comment is None:
            raise TaskConflictError("not_found", "comment not found")
        task = self._task(workspace_id, comment.task_id)
        comment = self.session.scalar(
            select(TaskComment)
            .where(TaskComment.id == comment_id, TaskComment.workspace_id == workspace_id, TaskComment.task_id == task.id)
            .with_for_update()
        )
        if comment is None:
            raise TaskConflictError("not_found", "comment not found")
        if comment.author_user_id != actor_user_id:
            raise TaskConflictError("approval_required", "comment author approval is required")
        fingerprint = request_fingerprint(
            f"/api/v1/tasks/{task.id}/comments/{comment.id}",
            {"base_version": base_version},
        )
        existing = self._existing_operation(workspace_id, actor_user_id, request_id)
        if existing is not None:
            if existing.base_versions != {"fingerprint": fingerprint}:
                raise TaskConflictError("idempotency_key_reused", "request id was used with a different payload")
            self.last_cursor = existing.cursor
            return comment
        if comment.deleted_at is not None:
            raise TaskConflictError("lifecycle_conflict", "comment already deleted")
        if comment.version != base_version:
            raise TaskConflictError("field_conflict", "comment changed", [])
        before = {"comment_id": str(comment.id), "body": comment.body, "version": comment.version, "deleted_at": None}
        comment.deleted_at = self.now()
        comment.deleted_by = actor_user_id
        comment.version += 1
        cursor = self._resource_cursor(workspace_id, "comment", comment.id, ChangeAction.UPDATED, request_id)
        self._operation(
            workspace_id,
            actor_user_id,
            request_id,
            task,
            OperationType.UPDATED,
            self.snapshot(task),
            {"task": self.snapshot(task), "comment": {**before, "deleted_at": comment.deleted_at.isoformat(), "deleted_by": str(actor_user_id), "version": comment.version}},
            cursor,
            base_versions={"fingerprint": fingerprint},
        )
        return comment

    def snapshot(self, task: Task) -> dict[str, Any]:
        raw_status = task.status.value if hasattr(task.status, "value") else str(task.status)
        public_status = "DONE" if raw_status == "COMPLETED" else raw_status
        public_progress = 0 if public_status == "TODO" else 100 if public_status == "DONE" else task.progress if public_status == "IN_PROGRESS" else None
        return {
            "id": str(task.id),
            "workspace_id": str(task.workspace_id),
            "parent_task_id": str(task.parent_task_id) if task.parent_task_id else None,
            "task_number": task.task_number,
            "title": task.title,
            "description": task.description,
            "due_at": task.due_at.isoformat() if task.due_at else None,
            "status": public_status,
            "quadrant": task.quadrant.value if isinstance(task.quadrant, TaskQuadrant) else task.quadrant,
            "labels": list(task.labels or []),
            "progress": public_progress,
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
            "delay_count": int(self.session.scalar(select(func.count(DelayRecord.id)).where(DelayRecord.task_id == task.id)) or 0),
            "total_delay_minutes": int(self.session.scalar(select(func.coalesce(func.sum(DelayRecord.delay_duration_minutes), 0)).where(DelayRecord.task_id == task.id)) or 0),
            "version": task.version,
            "field_versions": {
                key: value for key, value in (task.field_versions or {}).items() if key != "assignee_ids"
            },
            "lifecycle_version": task.lifecycle_version,
            "status_version": task.status_version,
            "deleted_at": task.deleted_at.isoformat() if task.deleted_at else None,
        }

    def _task(self, workspace_id: UUID, task_id: UUID) -> Task:
        task = self.session.scalar(select(Task).where(Task.id == task_id, Task.workspace_id == workspace_id).with_for_update())
        if task is None:
            raise TaskConflictError("not_found", "task not found")
        return task

    def _require_handler(self, task: Task, actor_user_id: UUID) -> None:
        if task.current_handler_id != actor_user_id:
            raise TaskConflictError("approval_required", "task owner approval is required")

    def _record_handler_change(
        self,
        task: Task,
        previous_handler_id: UUID | str | None,
        changed_by: UUID,
    ) -> None:
        if task.current_handler_id == previous_handler_id:
            return
        self.session.add(
            TaskHandlerHistory(
                task_id=task.id,
                from_user_id=previous_handler_id,
                to_user_id=task.current_handler_id,
                changed_by=changed_by,
            )
        )

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

    def _existing_operation(self, workspace_id: UUID, actor_user_id: UUID, request_id: UUID) -> TaskOperation | None:
        operation = self.session.scalar(select(TaskOperation).where(TaskOperation.workspace_id == workspace_id, TaskOperation.request_id == request_id))
        if operation is not None and operation.actor_user_id != actor_user_id:
            raise TaskConflictError("idempotency_key_reused", "request id belongs to another actor")
        return operation

    def _cursor(self, workspace_id: UUID, task: Task, action: ChangeAction, request_id: UUID) -> int:
        return self._resource_cursor(workspace_id, "task", task.id, action, request_id)

    def _resource_cursor(self, workspace_id: UUID, resource_type: str, resource_id: UUID, action: ChangeAction, request_id: UUID) -> int:
        cursor = Repository(self.session).allocate_workspace_cursor(workspace_id)
        self.session.add(WorkspaceChangeLog(workspace_id=workspace_id, cursor=cursor, resource_type=resource_type, resource_id=resource_id, action=action, operation_id=request_id))
        self.last_cursor = cursor
        return cursor

    def _operation(self, workspace_id: UUID, actor_user_id: UUID, request_id: UUID, task: Task, operation_type: OperationType, before: dict[str, Any] | None, after: dict[str, Any] | None, cursor: int, base_versions: dict[str, Any] | None = None) -> TaskOperation:
        self.session.add(
            ActivityEvent(
                workspace_id=workspace_id,
                task_id=task.id,
                actor_user_id=actor_user_id,
                event_type=operation_type.value,
                payload={"before": before, "after": after},
                request_id=request_id,
            )
        )
        operation = TaskOperation(workspace_id=workspace_id, task_id=task.id, actor_user_id=actor_user_id, request_id=request_id, operation_type=operation_type, before_state=before, after_state=after, base_versions=base_versions, resulting_versions=task.field_versions, cursor=cursor)
        self.session.add(operation)
        self.session.flush()
        return operation
