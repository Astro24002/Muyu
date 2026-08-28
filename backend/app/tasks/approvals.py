from __future__ import annotations

from copy import deepcopy
from dataclasses import dataclass
from datetime import datetime, timezone
from enum import Enum
from typing import Any, Callable, Literal, Mapping
from uuid import UUID, uuid4

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.enums import (
    ChangeAction,
    MembershipStatus,
    OperationType,
    TaskApprovalRequestStatus,
    TaskApprovalRequestType,
    TaskQuadrant,
    UserStatus,
)
from app.db.models import (
    ActivityEvent,
    Task,
    TaskApprovalRequest,
    TaskComment,
    TaskOperation,
    User,
    WorkspaceChangeLog,
    WorkspaceMembership,
)
from app.db.repositories.base import Repository
from app.tasks.conflicts import TaskConflictError
from app.tasks.service import MUTABLE_FIELDS, TaskService


TASK_UPDATE_FIELDS = MUTABLE_FIELDS - {"quadrant", "assignee_ids", "current_handler_id"}
STATUS_CHANGE_FIELDS = {
    "target_status",
    "blocked_reason",
    "resume_handler_id",
    "waiting_for_user_id",
}
class TaskApprovalError(TaskConflictError):
    """Stable domain error raised by the task approval service."""


ApprovalConflictError = TaskApprovalError


@dataclass(frozen=True)
class TaskApprovalResult:
    request: TaskApprovalRequest
    task: Task | None = None
    comment: TaskComment | None = None
    cursor: int | None = None

    @property
    def approval_request(self) -> TaskApprovalRequest:
        """Resource-oriented spelling used by the HTTP response layer."""

        return self.request

    @property
    def updated_request(self) -> TaskApprovalRequest:
        return self.request

    @property
    def updated_task(self) -> Task | None:
        return self.task

    @property
    def updated_comment(self) -> TaskComment | None:
        return self.comment


class TaskApprovalService:
    """Create and resolve fixed two-member task approval requests.

    The service deliberately delegates approved mutations to ``TaskService``.
    For task actions the derived task owner is passed as the actor, and for a
    comment deletion the derived comment author is passed as the actor.  This
    keeps the existing owner checks in one place and avoids adding an approval
    bypass to the task domain service.
    """

    def __init__(
        self,
        session: Session,
        *,
        now: Callable[[], datetime] = lambda: datetime.now(timezone.utc),
    ) -> None:
        self.session = session
        self.now = now
        self.last_cursor: int | None = None

    def create(
        self,
        workspace_id: UUID,
        requester_id: UUID,
        request_id: UUID,
        task_id: UUID,
        request_type: TaskApprovalRequestType,
        proposed_changes: dict[str, Any],
        base_field_versions: dict[str, int],
        comment_id: UUID | None = None,
    ) -> TaskApprovalRequest:
        workspace_id = self._uuid(workspace_id, "workspace_id")
        requester_id = self._uuid(requester_id, "requester_id")
        request_id = self._uuid(request_id, "request_id")
        task_id = self._uuid(task_id, "task_id")
        comment_id = self._uuid(comment_id, "comment_id") if comment_id is not None else None
        request_type = self._request_type(request_type)
        changes = self._normalize_changes(proposed_changes)
        versions = self._normalize_versions(base_field_versions)

        existing = self.session.scalar(
            select(TaskApprovalRequest)
            .where(
                TaskApprovalRequest.workspace_id == workspace_id,
                TaskApprovalRequest.request_id == request_id,
            )
            .with_for_update()
        )
        if existing is not None:
            if not self._same_request(existing, requester_id, task_id, comment_id, request_type, changes, versions):
                raise TaskApprovalError("approval_request_reused", "request id was used with a different approval request")
            self.last_cursor = self.session.scalar(
                select(WorkspaceChangeLog.cursor)
                .where(
                    WorkspaceChangeLog.workspace_id == workspace_id,
                    WorkspaceChangeLog.resource_type == "approval_request",
                    WorkspaceChangeLog.resource_id == existing.id,
                )
                .order_by(WorkspaceChangeLog.cursor.desc())
                .limit(1)
            )
            return existing
        self._validate_request_shape(request_type, changes, versions, comment_id)

        members = self._active_members(workspace_id)
        if len(members) != 2:
            raise TaskApprovalError("approval_not_allowed", "exactly two active workspace members are required")
        member_ids = {item.user_id for item in members}
        requester = self.session.get(User, requester_id)
        if requester_id not in member_ids or requester is None or requester.status != UserStatus.ACTIVE:
            raise TaskApprovalError("approval_not_allowed", "requester must be an active workspace member")

        task = self.session.scalar(
            select(Task)
            .where(Task.id == task_id, Task.workspace_id == workspace_id)
            .with_for_update()
        )
        if task is None:
            raise TaskApprovalError("approval_not_allowed", "task does not belong to the workspace")

        comment: TaskComment | None = None
        if comment_id is not None:
            comment = self.session.scalar(
                select(TaskComment)
                .where(
                    TaskComment.id == comment_id,
                    TaskComment.task_id == task.id,
                    TaskComment.workspace_id == workspace_id,
                )
                .with_for_update()
            )
            if comment is None:
                raise TaskApprovalError("approval_not_allowed", "comment does not belong to the task workspace")

        if request_type == TaskApprovalRequestType.COMMENT_DELETE:
            if comment is None or comment.deleted_at is not None:
                raise TaskApprovalError("approval_not_allowed", "comment is not available for deletion")
            if comment.author_user_id == requester_id:
                raise TaskApprovalError("approval_not_allowed", "comment authors can delete their own comments directly")
            if comment.author_user_id not in member_ids:
                raise TaskApprovalError("approval_not_allowed", "comment author must be an active workspace member")
            approver_id = comment.author_user_id
        else:
            if comment_id is not None:
                raise TaskApprovalError("approval_not_allowed", "comment_id is only valid for comment deletion")
            if task.current_handler_id is None or task.current_handler_id not in member_ids:
                raise TaskApprovalError("approval_not_allowed", "task owner must be an active workspace member")
            if task.current_handler_id == requester_id:
                raise TaskApprovalError("approval_not_allowed", "task owner writes do not require approval")
            approver_id = task.current_handler_id
            if task.deleted_at is not None and request_type != TaskApprovalRequestType.TASK_RESTORE:
                raise TaskApprovalError("approval_not_allowed", "deleted tasks cannot receive this approval request")
            if request_type == TaskApprovalRequestType.TASK_RESTORE and task.deleted_at is None:
                raise TaskApprovalError("approval_not_allowed", "only deleted tasks can be restored")

        request = TaskApprovalRequest(
            workspace_id=workspace_id,
            task_id=task.id,
            comment_id=comment.id if comment is not None else None,
            requester_id=requester_id,
            approver_id=approver_id,
            request_type=request_type,
            proposed_changes=deepcopy(changes),
            base_field_versions=deepcopy(versions),
            request_id=request_id,
            status=TaskApprovalRequestStatus.PENDING,
        )
        self.session.add(request)
        self.session.flush()
        self._emit_request_event(
            request,
            task,
            actor_user_id=requester_id,
            action_request_id=request_id,
            event_type="APPROVAL_REQUESTED",
            change_action=ChangeAction.CREATED,
        )
        return request

    def list(
        self,
        workspace_id: UUID,
        viewer_id: UUID,
        box: Literal["incoming", "outgoing"] | None = None,
    ) -> list[TaskApprovalRequest]:
        workspace_id = self._uuid(workspace_id, "workspace_id")
        viewer_id = self._uuid(viewer_id, "viewer_id")
        if box not in {None, "incoming", "outgoing"}:
            raise TaskApprovalError("approval_not_allowed", "box must be incoming or outgoing")
        self._require_active_principal(workspace_id, viewer_id)
        statement = select(TaskApprovalRequest).where(TaskApprovalRequest.workspace_id == workspace_id)
        if box == "incoming":
            statement = statement.where(
                TaskApprovalRequest.approver_id == viewer_id,
                TaskApprovalRequest.status == TaskApprovalRequestStatus.PENDING,
            )
        elif box == "outgoing":
            statement = statement.where(TaskApprovalRequest.requester_id == viewer_id)
        else:
            statement = statement.where(
                (TaskApprovalRequest.requester_id == viewer_id)
                | (TaskApprovalRequest.approver_id == viewer_id)
            )
        return list(
            self.session.scalars(
                statement.order_by(TaskApprovalRequest.created_at.desc(), TaskApprovalRequest.id.desc())
            ).all()
        )

    def approve(
        self,
        workspace_id: UUID,
        approver_id: UUID,
        approval_id: UUID,
        action_request_id: UUID,
    ) -> TaskApprovalResult:
        workspace_id = self._uuid(workspace_id, "workspace_id")
        approver_id = self._uuid(approver_id, "approver_id")
        approval_id = self._uuid(approval_id, "approval_id")
        action_request_id = self._uuid(action_request_id, "action_request_id")
        request = self._request(workspace_id, approval_id)
        action = self._existing_action(workspace_id, action_request_id, approval_id, "approve")
        if action is not None:
            self.last_cursor = action.cursor
            return self._result_from_request(request, action.cursor)
        self._require_pending(request)
        self._require_active_principal(workspace_id, approver_id)
        if request.approver_id != approver_id or request.requester_id == approver_id:
            raise TaskApprovalError("approval_not_allowed", "only the derived approver may approve this request")

        task, comment = self._lock_target(request)
        self._check_freshness(request, task, comment, action_request_id)
        target_actor = comment.author_user_id if request.request_type == TaskApprovalRequestType.COMMENT_DELETE and comment else task.current_handler_id
        if target_actor is None or target_actor != request.approver_id:
            self._cancel_for_stale_owner(request, task, comment, action_request_id, "task owner changed")
        try:
            target_task, target_comment = self._apply(request, task, comment, target_actor)
        except TaskConflictError as error:
            self._mark_conflicted(request, task, comment, action_request_id, str(error))
            raise TaskApprovalError("approval_conflicted", str(error)) from error

        if request.request_type == TaskApprovalRequestType.HANDLER_TRANSFER:
            self._cancel_pending_for_task(workspace_id, task.id, "task handler changed", exclude={request.id})
        elif request.request_type == TaskApprovalRequestType.TASK_DELETE:
            self._cancel_pending_for_task(workspace_id, task.id, "task was deleted", exclude={request.id})
        elif request.request_type == TaskApprovalRequestType.TASK_RESTORE:
            self._cancel_pending_for_task(workspace_id, task.id, "task was restored", exclude={request.id})

        request.status = TaskApprovalRequestStatus.APPROVED
        request.reviewed_at = self.now()
        request.reviewed_by = approver_id
        request.rejection_reason = None
        cursor = self._emit_request_event(
            request,
            task,
            actor_user_id=approver_id,
            action_request_id=action_request_id,
            event_type="APPROVAL_APPROVED",
            change_action=ChangeAction.UPDATED,
        )
        request.resolved_cursor = cursor
        self.session.flush()
        return TaskApprovalResult(request=request, task=target_task, comment=target_comment, cursor=cursor)

    def reject(
        self,
        workspace_id: UUID,
        approver_id: UUID,
        approval_id: UUID,
        action_request_id: UUID,
        reason: str | None = None,
    ) -> TaskApprovalRequest:
        workspace_id = self._uuid(workspace_id, "workspace_id")
        approver_id = self._uuid(approver_id, "approver_id")
        approval_id = self._uuid(approval_id, "approval_id")
        action_request_id = self._uuid(action_request_id, "action_request_id")
        request = self._request(workspace_id, approval_id)
        action = self._existing_action(workspace_id, action_request_id, approval_id, "reject")
        if action is not None:
            self.last_cursor = action.cursor
            return request
        self._require_pending(request)
        self._require_active_principal(workspace_id, approver_id)
        if request.approver_id != approver_id or request.requester_id == approver_id:
            raise TaskApprovalError("approval_not_allowed", "only the derived approver may reject this request")
        task, comment = self._lock_target(request)
        request.status = TaskApprovalRequestStatus.REJECTED
        request.reviewed_at = self.now()
        request.reviewed_by = approver_id
        request.rejection_reason = reason.strip() if isinstance(reason, str) and reason.strip() else None
        cursor = self._emit_request_event(
            request,
            task,
            actor_user_id=approver_id,
            action_request_id=action_request_id,
            event_type="APPROVAL_REJECTED",
            change_action=ChangeAction.UPDATED,
        )
        request.resolved_cursor = cursor
        self.session.flush()
        return request

    def cancel(
        self,
        workspace_id: UUID,
        requester_id: UUID,
        approval_id: UUID,
        action_request_id: UUID,
    ) -> TaskApprovalRequest:
        workspace_id = self._uuid(workspace_id, "workspace_id")
        requester_id = self._uuid(requester_id, "requester_id")
        approval_id = self._uuid(approval_id, "approval_id")
        action_request_id = self._uuid(action_request_id, "action_request_id")
        request = self._request(workspace_id, approval_id)
        action = self._existing_action(workspace_id, action_request_id, approval_id, "cancel")
        if action is not None:
            self.last_cursor = action.cursor
            return request
        self._require_pending(request)
        self._require_active_principal(workspace_id, requester_id)
        if request.requester_id != requester_id:
            raise TaskApprovalError("approval_not_allowed", "only the requester may cancel this request")
        task, comment = self._lock_target(request)
        request.status = TaskApprovalRequestStatus.CANCELLED
        request.reviewed_at = self.now()
        request.reviewed_by = requester_id
        request.rejection_reason = "cancelled by requester"
        cursor = self._emit_request_event(
            request,
            task,
            actor_user_id=requester_id,
            action_request_id=action_request_id,
            event_type="APPROVAL_CANCELLED",
            change_action=ChangeAction.UPDATED,
        )
        request.resolved_cursor = cursor
        self.session.flush()
        return request

    def cancel_stale_for_task(self, workspace_id: UUID, task_id: UUID, reason: str) -> int:
        return self._cancel_pending_for_task(workspace_id, task_id, reason)

    def _cancel_pending_for_task(
        self,
        workspace_id: UUID,
        task_id: UUID,
        reason: str,
        *,
        exclude: set[UUID] | None = None,
    ) -> int:
        workspace_id = self._uuid(workspace_id, "workspace_id")
        task_id = self._uuid(task_id, "task_id")
        task = self.session.scalar(
            select(Task)
            .where(Task.id == task_id, Task.workspace_id == workspace_id)
            .with_for_update()
        )
        if task is None:
            raise TaskApprovalError("approval_not_found", "task not found")
        pending = list(
            self.session.scalars(
                select(TaskApprovalRequest)
                .where(
                    TaskApprovalRequest.workspace_id == workspace_id,
                    TaskApprovalRequest.task_id == task_id,
                    TaskApprovalRequest.status == TaskApprovalRequestStatus.PENDING,
                )
                .with_for_update()
            ).all()
        )
        handler_change = any(word in reason.lower() for word in ("handler", "owner", "transfer"))
        count = 0
        for request in pending:
            if exclude and request.id in exclude:
                continue
            if handler_change and task.current_handler_id is not None and request.approver_id == task.current_handler_id:
                continue
            request.status = TaskApprovalRequestStatus.CANCELLED
            request.reviewed_at = self.now()
            request.reviewed_by = None
            request.rejection_reason = reason
            self._emit_request_event(
                request,
                task,
                actor_user_id=request.requester_id,
                action_request_id=uuid4(),
                event_type="APPROVAL_CANCELLED",
                change_action=ChangeAction.UPDATED,
            )
            count += 1
        self.session.flush()
        return count

    def _apply(
        self,
        request: TaskApprovalRequest,
        task: Task,
        comment: TaskComment | None,
        target_actor: UUID | None,
    ) -> tuple[Task | None, TaskComment | None]:
        if target_actor is None:
            raise TaskApprovalError("approval_conflicted", "approved target has no owner")
        service = TaskService(self.session, now=self.now)
        request_type = request.request_type
        changes = self._decoded_changes(request.proposed_changes)
        versions = {key: int(value) for key, value in (request.base_field_versions or {}).items()}
        if request_type == TaskApprovalRequestType.TASK_UPDATE:
            return service.patch(task.workspace_id, target_actor, task.id, request.id, changes, versions), None
        if request_type == TaskApprovalRequestType.QUADRANT_UPDATE:
            return service.patch(task.workspace_id, target_actor, task.id, request.id, changes, versions), None
        if request_type == TaskApprovalRequestType.ASSIGNEE_UPDATE:
            return service.patch(task.workspace_id, target_actor, task.id, request.id, changes, versions), None
        if request_type == TaskApprovalRequestType.HANDLER_TRANSFER:
            return service.patch(task.workspace_id, target_actor, task.id, request.id, changes, versions), None
        if request_type == TaskApprovalRequestType.STATUS_UPDATE:
            status_version = self._base_version(request, "status_version", "status")
            if status_version is None:
                raise TaskApprovalError("approval_conflicted", "status version is required")
            return (
                service.transition(
                    task.workspace_id,
                    target_actor,
                    task.id,
                    request.id,
                    str(changes["target_status"]),
                    status_version,
                    changes.get("blocked_reason"),
                    self._optional_uuid(changes.get("resume_handler_id")),
                    self._optional_uuid(changes.get("waiting_for_user_id")),
                ),
                None,
            )
        if request_type == TaskApprovalRequestType.TASK_DELETE:
            lifecycle_version = self._base_version(request, "lifecycle_version", "lifecycle")
            if lifecycle_version is None:
                raise TaskApprovalError("approval_conflicted", "lifecycle version is required")
            return service.lifecycle(task.workspace_id, target_actor, task.id, request.id, "delete", lifecycle_version), None
        if request_type == TaskApprovalRequestType.TASK_RESTORE:
            lifecycle_version = self._base_version(request, "lifecycle_version", "lifecycle")
            if lifecycle_version is None:
                raise TaskApprovalError("approval_conflicted", "lifecycle version is required")
            return service.restore(task.workspace_id, target_actor, task.id, request.id, lifecycle_version), None
        if request_type == TaskApprovalRequestType.COMMENT_DELETE:
            if comment is None:
                raise TaskApprovalError("approval_conflicted", "comment not found")
            version = self._base_version(request, "version", "comment_version")
            if version is None:
                raise TaskApprovalError("approval_conflicted", "comment version is required")
            return None, service.delete_comment(task.workspace_id, target_actor, comment.id, request.id, version)
        raise TaskApprovalError("approval_not_allowed", "unsupported approval request type")

    def _check_freshness(
        self,
        request: TaskApprovalRequest,
        task: Task,
        comment: TaskComment | None,
        action_request_id: UUID,
    ) -> None:
        if request.request_type == TaskApprovalRequestType.COMMENT_DELETE:
            if comment is None or comment.deleted_at is not None or task.deleted_at is not None:
                self._cancel_for_stale_owner(request, task, comment, action_request_id, "comment or task lifecycle changed")
            version = self._base_version(request, "version", "comment_version")
            if version is None or comment.version != version:
                self._mark_conflicted(request, task, comment, action_request_id, "comment version changed")
            if comment.author_user_id != request.approver_id:
                self._cancel_for_stale_owner(request, task, comment, action_request_id, "comment author changed")
            return

        if task.current_handler_id != request.approver_id:
            self._cancel_for_stale_owner(request, task, comment, action_request_id, "task handler changed")
        if task.deleted_at is not None and request.request_type != TaskApprovalRequestType.TASK_RESTORE:
            self._cancel_for_stale_owner(request, task, comment, action_request_id, "task was deleted")
        if request.request_type == TaskApprovalRequestType.TASK_RESTORE and task.deleted_at is None:
            self._mark_conflicted(request, task, comment, action_request_id, "task was restored")

        if request.request_type in {
            TaskApprovalRequestType.TASK_DELETE,
            TaskApprovalRequestType.TASK_RESTORE,
        }:
            expected = self._base_version(request, "lifecycle_version", "lifecycle")
            if expected is None or task.lifecycle_version != expected:
                self._mark_conflicted(request, task, comment, action_request_id, "task lifecycle version changed")
            return
        if request.request_type == TaskApprovalRequestType.STATUS_UPDATE:
            expected = self._base_version(request, "status_version", "status")
            if expected is None or task.status_version != expected:
                self._mark_conflicted(request, task, comment, action_request_id, "task status version changed")
            return
        current_versions = dict(task.field_versions or {})
        for field in request.proposed_changes:
            expected = (request.base_field_versions or {}).get(field)
            if expected is None or int(current_versions.get(field, 1)) != int(expected):
                self._mark_conflicted(request, task, comment, action_request_id, f"task field {field} changed")

    def _mark_conflicted(
        self,
        request: TaskApprovalRequest,
        task: Task,
        comment: TaskComment | None,
        action_request_id: UUID,
        reason: str,
    ) -> None:
        request.status = TaskApprovalRequestStatus.CONFLICTED
        request.reviewed_at = self.now()
        request.reviewed_by = None
        request.rejection_reason = reason
        cursor = self._emit_request_event(
            request,
            task,
            actor_user_id=request.requester_id,
            action_request_id=action_request_id,
            event_type="APPROVAL_CONFLICTED",
            change_action=ChangeAction.UPDATED,
        )
        request.resolved_cursor = cursor
        self.session.flush()
        raise TaskApprovalError("approval_conflicted", reason)

    def _cancel_for_stale_owner(
        self,
        request: TaskApprovalRequest,
        task: Task,
        comment: TaskComment | None,
        action_request_id: UUID,
        reason: str,
    ) -> None:
        request.status = TaskApprovalRequestStatus.CANCELLED
        request.reviewed_at = self.now()
        request.reviewed_by = None
        request.rejection_reason = reason
        cursor = self._emit_request_event(
            request,
            task,
            actor_user_id=request.requester_id,
            action_request_id=action_request_id,
            event_type="APPROVAL_CANCELLED",
            change_action=ChangeAction.UPDATED,
        )
        request.resolved_cursor = cursor
        self.session.flush()
        raise TaskApprovalError("approval_conflicted", reason)

    def _active_members(self, workspace_id: UUID) -> list[WorkspaceMembership]:
        return list(
            self.session.scalars(
                select(WorkspaceMembership)
                .where(
                    WorkspaceMembership.workspace_id == workspace_id,
                    WorkspaceMembership.status == MembershipStatus.ACTIVE,
                )
                .order_by(WorkspaceMembership.member_slot, WorkspaceMembership.user_id)
                .with_for_update()
            ).all()
        )

    def _require_active_principal(self, workspace_id: UUID, user_id: UUID) -> None:
        user = self.session.scalar(select(User).where(User.id == user_id))
        member = self.session.scalar(
            select(WorkspaceMembership.id).where(
                WorkspaceMembership.workspace_id == workspace_id,
                WorkspaceMembership.user_id == user_id,
                WorkspaceMembership.status == MembershipStatus.ACTIVE,
            )
        )
        if user is None or user.status != UserStatus.ACTIVE or member is None:
            raise TaskApprovalError("approval_not_allowed", "active writable principal is required")

    def _request(self, workspace_id: UUID, approval_id: UUID) -> TaskApprovalRequest:
        request = self.session.scalar(
            select(TaskApprovalRequest)
            .where(
                TaskApprovalRequest.id == approval_id,
                TaskApprovalRequest.workspace_id == workspace_id,
            )
            .with_for_update()
        )
        if request is None:
            raise TaskApprovalError("approval_not_found", "approval request not found")
        return request

    def _lock_target(self, request: TaskApprovalRequest) -> tuple[Task, TaskComment | None]:
        task = self.session.scalar(
            select(Task)
            .where(Task.id == request.task_id, Task.workspace_id == request.workspace_id)
            .with_for_update()
        )
        if task is None:
            raise TaskApprovalError("approval_not_found", "approval target not found")
        comment = None
        if request.comment_id is not None:
            comment = self.session.scalar(
                select(TaskComment)
                .where(
                    TaskComment.id == request.comment_id,
                    TaskComment.task_id == task.id,
                    TaskComment.workspace_id == request.workspace_id,
                )
                .with_for_update()
            )
            if comment is None:
                raise TaskApprovalError("approval_not_found", "approval comment target not found")
        return task, comment

    def _require_pending(self, request: TaskApprovalRequest) -> None:
        if request.status != TaskApprovalRequestStatus.PENDING:
            raise TaskApprovalError("approval_already_resolved", "approval request is already resolved")

    def _existing_action(
        self,
        workspace_id: UUID,
        action_request_id: UUID,
        approval_id: UUID,
        action_name: str,
    ) -> TaskOperation | None:
        operation = self.session.scalar(
            select(TaskOperation).where(
                TaskOperation.workspace_id == workspace_id,
                TaskOperation.request_id == action_request_id,
            )
        )
        if operation is None:
            return None
        metadata = operation.base_versions or {}
        actual_action = metadata.get("approval_action")
        if metadata.get("approval_id") != str(approval_id):
            raise TaskApprovalError("approval_request_reused", "action request id was used for another operation")
        if action_name == "approve" and actual_action in {"cancel", "conflict"}:
            return operation
        if actual_action != action_name:
            raise TaskApprovalError("approval_request_reused", "action request id was used for another operation")
        return operation

    def _result_from_request(self, request: TaskApprovalRequest, cursor: int | None) -> TaskApprovalResult:
        task = self.session.get(Task, request.task_id)
        comment = self.session.get(TaskComment, request.comment_id) if request.comment_id is not None else None
        return TaskApprovalResult(
            request=request,
            task=task,
            comment=comment,
            cursor=request.resolved_cursor if request.resolved_cursor is not None else cursor,
        )

    def _emit_request_event(
        self,
        request: TaskApprovalRequest,
        task: Task,
        *,
        actor_user_id: UUID,
        action_request_id: UUID,
        event_type: str,
        change_action: ChangeAction,
    ) -> int:
        payload = self._request_payload(request)
        cursor = Repository(self.session).allocate_workspace_cursor(request.workspace_id)
        self.session.add(
            WorkspaceChangeLog(
                workspace_id=request.workspace_id,
                cursor=cursor,
                resource_type="approval_request",
                resource_id=request.id,
                action=change_action,
                operation_id=action_request_id,
            )
        )
        self.session.add(
            ActivityEvent(
                workspace_id=request.workspace_id,
                task_id=task.id,
                actor_user_id=actor_user_id,
                event_type=event_type,
                payload={"approval_request": payload, "reason": request.rejection_reason},
                request_id=action_request_id,
            )
        )
        action_name = {
            "APPROVAL_REQUESTED": "create",
            "APPROVAL_APPROVED": "approve",
            "APPROVAL_REJECTED": "reject",
            "APPROVAL_CANCELLED": "cancel",
            "APPROVAL_CONFLICTED": "conflict",
        }.get(event_type, event_type.removeprefix("APPROVAL_").lower())
        self.session.add(
            TaskOperation(
                workspace_id=request.workspace_id,
                task_id=task.id,
                actor_user_id=actor_user_id,
                request_id=action_request_id,
                operation_type=OperationType.UPDATED,
                before_state={"approval_request_id": str(request.id)},
                after_state={"approval_request": payload},
                base_versions={"approval_action": action_name, "approval_id": str(request.id)},
                resulting_versions=task.field_versions,
                cursor=cursor,
            )
        )
        self.session.flush()
        self.last_cursor = cursor
        return cursor

    def _request_payload(self, request: TaskApprovalRequest) -> dict[str, Any]:
        return {
            "id": str(request.id),
            "workspace_id": str(request.workspace_id),
            "task_id": str(request.task_id),
            "comment_id": str(request.comment_id) if request.comment_id is not None else None,
            "requester_id": str(request.requester_id),
            "approver_id": str(request.approver_id),
            "request_type": request.request_type.value,
            "proposed_changes": deepcopy(request.proposed_changes or {}),
            "base_field_versions": deepcopy(request.base_field_versions or {}),
            "request_id": str(request.request_id),
            "status": request.status.value,
            "created_at": request.created_at.isoformat() if request.created_at else None,
            "reviewed_at": request.reviewed_at.isoformat() if request.reviewed_at else None,
            "reviewed_by": str(request.reviewed_by) if request.reviewed_by is not None else None,
            "rejection_reason": request.rejection_reason,
            "resolved_cursor": request.resolved_cursor,
        }

    def _validate_request_shape(
        self,
        request_type: TaskApprovalRequestType,
        changes: dict[str, Any],
        versions: dict[str, int],
        comment_id: UUID | None,
    ) -> None:
        if request_type == TaskApprovalRequestType.TASK_UPDATE:
            if not changes or set(changes) - TASK_UPDATE_FIELDS or set(changes) != set(versions):
                raise TaskApprovalError("approval_not_allowed", "task update fields and versions are invalid")
            if "progress" in changes and changes["progress"] not in {None, 20, 40, 60, 80}:
                raise TaskApprovalError("approval_not_allowed", "progress must be 20, 40, 60, or 80")
        elif request_type == TaskApprovalRequestType.QUADRANT_UPDATE:
            if set(changes) != {"quadrant"} or set(versions) != {"quadrant"}:
                raise TaskApprovalError("approval_not_allowed", "quadrant update requires the quadrant field version")
            if changes["quadrant"] is not None and changes["quadrant"] not in {item.value for item in TaskQuadrant}:
                raise TaskApprovalError("approval_not_allowed", "quadrant must be Q1, Q2, Q3, or Q4")
        elif request_type == TaskApprovalRequestType.STATUS_UPDATE:
            if "target_status" not in changes or set(changes) - STATUS_CHANGE_FIELDS:
                raise TaskApprovalError("approval_not_allowed", "status update fields are invalid")
            if set(versions) not in ({"status_version"}, {"status"}):
                raise TaskApprovalError("approval_not_allowed", "status version is required")
            if changes["target_status"] not in {"TODO", "IN_PROGRESS", "WAITING", "DONE", "CANCELLED"}:
                raise TaskApprovalError("approval_not_allowed", "unsupported target status")
        elif request_type in {TaskApprovalRequestType.TASK_DELETE, TaskApprovalRequestType.TASK_RESTORE}:
            if changes or set(versions) not in ({"lifecycle_version"}, {"lifecycle"}):
                raise TaskApprovalError("approval_not_allowed", "lifecycle approval fields are invalid")
        elif request_type == TaskApprovalRequestType.COMMENT_DELETE:
            if comment_id is None or changes or set(versions) not in ({"version"}, {"comment_version"}):
                raise TaskApprovalError("approval_not_allowed", "comment deletion requires the comment version")
        elif request_type == TaskApprovalRequestType.ASSIGNEE_UPDATE:
            if set(changes) != {"assignee_ids"} or set(versions) != {"assignee_ids"}:
                raise TaskApprovalError("approval_not_allowed", "assignee update requires assignee_ids")
            self._validate_assignee_values(changes["assignee_ids"])
        elif request_type == TaskApprovalRequestType.HANDLER_TRANSFER:
            if set(changes) != {"current_handler_id"} or set(versions) != {"current_handler_id"}:
                raise TaskApprovalError("approval_not_allowed", "handler transfer requires current_handler_id")
            self._uuid(changes["current_handler_id"], "current_handler_id")
        if request_type != TaskApprovalRequestType.COMMENT_DELETE and comment_id is not None:
            raise TaskApprovalError("approval_not_allowed", "comment_id is only valid for comment deletion")

    def _validate_assignee_values(self, values: Any) -> None:
        if not isinstance(values, list) or len(values) not in (1, 2):
            raise TaskApprovalError("approval_not_allowed", "assignee_ids must contain one or two users")
        try:
            normalized = [self._uuid(value, "assignee_id") for value in values]
        except TaskApprovalError:
            raise
        if len(set(normalized)) != len(normalized):
            raise TaskApprovalError("approval_not_allowed", "assignee_ids must be unique")

    def _same_request(
        self,
        request: TaskApprovalRequest,
        requester_id: UUID,
        task_id: UUID,
        comment_id: UUID | None,
        request_type: TaskApprovalRequestType,
        changes: dict[str, Any],
        versions: dict[str, int],
    ) -> bool:
        return (
            request.requester_id == requester_id
            and request.task_id == task_id
            and request.comment_id == comment_id
            and request.request_type == request_type
            and (request.proposed_changes or {}) == changes
            and (request.base_field_versions or {}) == versions
        )

    def _request_type(self, value: TaskApprovalRequestType | str) -> TaskApprovalRequestType:
        try:
            return value if isinstance(value, TaskApprovalRequestType) else TaskApprovalRequestType(str(value))
        except (TypeError, ValueError) as error:
            raise TaskApprovalError("approval_not_allowed", "unsupported approval request type") from error

    def _normalize_changes(self, value: Mapping[str, Any]) -> dict[str, Any]:
        if not isinstance(value, Mapping):
            raise TaskApprovalError("approval_not_allowed", "proposed_changes must be an object")
        normalized = self._json_value(value)
        if not isinstance(normalized, dict):  # pragma: no cover - guarded by Mapping above
            raise TaskApprovalError("approval_not_allowed", "proposed_changes must be an object")
        if "handler_id" in normalized and "current_handler_id" not in normalized:
            normalized["current_handler_id"] = normalized.pop("handler_id")
        if "status" in normalized and "target_status" not in normalized:
            normalized["target_status"] = normalized.pop("status")
        return normalized

    def _normalize_versions(self, value: Mapping[str, int]) -> dict[str, int]:
        if not isinstance(value, Mapping):
            raise TaskApprovalError("approval_not_allowed", "base_field_versions must be an object")
        normalized: dict[str, int] = {}
        for key, raw_value in value.items():
            if isinstance(raw_value, bool):
                raise TaskApprovalError("approval_not_allowed", "base versions must be integers")
            try:
                version = int(raw_value)
            except (TypeError, ValueError) as error:
                raise TaskApprovalError("approval_not_allowed", "base versions must be integers") from error
            if version < 1:
                raise TaskApprovalError("approval_not_allowed", "base versions must be positive")
            normalized[str(key)] = version
        if "lifecycle" in normalized and "lifecycle_version" not in normalized:
            normalized["lifecycle_version"] = normalized.pop("lifecycle")
        if "status" in normalized and "status_version" not in normalized:
            normalized["status_version"] = normalized.pop("status")
        if "comment_version" in normalized and "version" not in normalized:
            normalized["version"] = normalized.pop("comment_version")
        if "comment" in normalized and "version" not in normalized:
            normalized["version"] = normalized.pop("comment")
        if "handler_id" in normalized and "current_handler_id" not in normalized:
            normalized["current_handler_id"] = normalized.pop("handler_id")
        return normalized

    def _decoded_changes(self, changes: Mapping[str, Any]) -> dict[str, Any]:
        decoded = deepcopy(dict(changes))
        for field in ("due_at", "planned_start_at"):
            if isinstance(decoded.get(field), str):
                try:
                    decoded[field] = datetime.fromisoformat(decoded[field])
                except ValueError as error:
                    raise TaskApprovalError("approval_not_allowed", f"invalid {field}") from error
        if "assignee_ids" in decoded:
            self._validate_assignee_values(decoded["assignee_ids"])
            decoded["assignee_ids"] = [self._uuid(value, "assignee_id") for value in decoded["assignee_ids"]]
        if "current_handler_id" in decoded and decoded["current_handler_id"] is not None:
            decoded["current_handler_id"] = self._uuid(decoded["current_handler_id"], "current_handler_id")
        return decoded

    def _json_value(self, value: Any) -> Any:
        if isinstance(value, UUID):
            return str(value)
        if isinstance(value, datetime):
            return value.isoformat()
        if isinstance(value, Enum):
            return self._json_value(value.value)
        if isinstance(value, Mapping):
            return {str(key): self._json_value(item) for key, item in value.items()}
        if isinstance(value, (list, tuple, set)):
            return [self._json_value(item) for item in value]
        return value

    def _base_version(self, request: TaskApprovalRequest, *names: str) -> int | None:
        versions = request.base_field_versions or {}
        for name in names:
            if name in versions:
                return int(versions[name])
        return None

    def _optional_uuid(self, value: Any) -> UUID | None:
        if value is None:
            return None
        return self._uuid(value, "user_id")

    def _uuid(self, value: Any, field: str) -> UUID:
        try:
            return value if isinstance(value, UUID) else UUID(str(value))
        except (TypeError, ValueError) as error:
            raise TaskApprovalError("approval_not_allowed", f"invalid {field}") from error


__all__ = [
    "ApprovalConflictError",
    "TaskApprovalError",
    "TaskApprovalResult",
    "TaskApprovalService",
]
