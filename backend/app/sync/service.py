from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.enums import MembershipStatus
from app.auth.profile import public_display_name
from app.db.models import Task, TaskApprovalRequest, TaskComment, TaskConflict, User, Workspace, WorkspaceChangeLog, WorkspaceCursor, WorkspaceMembership
from app.tasks.approval_schemas import approval_request_json, comment_json
from app.tasks.operations import task_conflict_json
from app.tasks.service import TaskService


class SyncCursorExpired(Exception):
    pass


class SyncService:
    def __init__(self, session: Session, *, retention_days: int = 30) -> None:
        self.session = session
        self.retention_days = retention_days

    def snapshot(self, workspace_id: UUID, viewer_user_id: UUID | None = None) -> dict[str, Any]:
        workspace = self.session.get(Workspace, workspace_id)
        if workspace is None:
            raise ValueError("workspace not found")
        member_rows = self.session.execute(
            select(WorkspaceMembership, User)
            .join(User, User.id == WorkspaceMembership.user_id)
            .where(
                WorkspaceMembership.workspace_id == workspace_id,
                WorkspaceMembership.status == MembershipStatus.ACTIVE,
            )
            .order_by(WorkspaceMembership.member_slot.asc(), WorkspaceMembership.id.asc())
        ).all()
        tasks = self.session.scalars(select(Task).where(Task.workspace_id == workspace_id, Task.deleted_at.is_(None)).order_by(Task.updated_at.desc())).all()
        conflicts = self.session.scalars(
            select(TaskConflict)
            .where(TaskConflict.workspace_id == workspace_id, TaskConflict.status == "OPEN")
            .order_by(TaskConflict.created_at.asc(), TaskConflict.id.asc())
        ).all()
        cursor_row = self.session.get(WorkspaceCursor, workspace_id)
        head = max(0, (cursor_row.next_cursor - 1) if cursor_row else 0)
        # Keep task-derived fields identical across sync and HTTP responses.
        service = TaskService(self.session)
        task_snapshots = [service.snapshot(task) for task in tasks]
        task_snapshots_by_id = {item["id"]: item for item in task_snapshots}
        conflict_projections = []
        for conflict in conflicts:
            current_snapshot = task_snapshots_by_id.get(str(conflict.task_id))
            if current_snapshot is None:
                conflict_task = self.session.scalar(
                    select(Task).where(
                        Task.id == conflict.task_id,
                        Task.workspace_id == workspace_id,
                    )
                )
                if conflict_task is not None:
                    current_snapshot = service.snapshot(conflict_task)
            conflict_projections.append(task_conflict_json(conflict, current_snapshot))
        comments = self.session.scalars(
            select(TaskComment)
            .where(TaskComment.workspace_id == workspace_id)
            .order_by(TaskComment.created_at.asc(), TaskComment.id.asc())
        ).all()
        approvals = self.session.scalars(
            select(TaskApprovalRequest)
            .where(TaskApprovalRequest.workspace_id == workspace_id)
            .order_by(TaskApprovalRequest.created_at.asc(), TaskApprovalRequest.id.asc())
        ).all()
        return {
            "workspace_id": str(workspace_id),
            "viewer_user_id": str(viewer_user_id) if viewer_user_id else None,
            "workspace": {"id": str(workspace.id), "name": workspace.name, "status": workspace.status.value},
            "members": [
                {
                    "user_id": str(membership.user_id),
                    "display_name": public_display_name(user),
                    "member_slot": membership.member_slot,
                }
                for membership, user in member_rows
            ],
            "tasks": task_snapshots,
            "conflicts": conflict_projections,
            "comments": [comment_json(item) for item in comments],
            "approval_requests": [approval_request_json(item) for item in approvals],
            "cursor": head,
        }

    def changes(self, workspace_id: UUID, after_cursor: int, limit: int = 100) -> dict[str, Any]:
        oldest = self.session.scalar(select(WorkspaceChangeLog.cursor).where(WorkspaceChangeLog.workspace_id == workspace_id).order_by(WorkspaceChangeLog.created_at.asc()).limit(1))
        if oldest is not None and after_cursor < oldest - 1:
            raise SyncCursorExpired("sync cursor expired")
        rows = self.session.scalars(select(WorkspaceChangeLog).where(WorkspaceChangeLog.workspace_id == workspace_id, WorkspaceChangeLog.cursor > after_cursor).order_by(WorkspaceChangeLog.cursor.asc()).limit(min(500, max(1, limit)))).all()
        changes = []
        for item in rows:
            resource = None
            if item.resource_type == "task":
                task = self.session.scalar(
                    select(Task).where(
                        Task.id == item.resource_id,
                        Task.workspace_id == workspace_id,
                    )
                )
                if task is not None:
                    resource = TaskService(self.session).snapshot(task)
            elif item.resource_type == "comment":
                comment = self.session.scalar(
                    select(TaskComment).where(
                        TaskComment.id == item.resource_id,
                        TaskComment.workspace_id == workspace_id,
                    )
                )
                if comment is not None:
                    resource = comment_json(comment)
            elif item.resource_type == "approval_request":
                approval = self.session.scalar(
                    select(TaskApprovalRequest).where(
                        TaskApprovalRequest.id == item.resource_id,
                        TaskApprovalRequest.workspace_id == workspace_id,
                    )
                )
                if approval is not None:
                    resource = approval_request_json(approval)
            elif item.resource_type == "task_conflict":
                conflict = self.session.scalar(
                    select(TaskConflict).where(
                        TaskConflict.id == item.resource_id,
                        TaskConflict.workspace_id == workspace_id,
                    )
                )
                if conflict is not None:
                    conflict_task = self.session.scalar(
                        select(Task).where(
                            Task.id == conflict.task_id,
                            Task.workspace_id == workspace_id,
                        )
                    )
                    current_snapshot = (
                        TaskService(self.session).snapshot(conflict_task)
                        if conflict_task is not None
                        else None
                    )
                    resource = task_conflict_json(conflict, current_snapshot)
            changes.append({"cursor": item.cursor, "resource_type": item.resource_type, "resource_id": str(item.resource_id), "action": item.action.value, "operation_id": str(item.operation_id) if item.operation_id else None, "resource": resource})
        return {
            "workspace_id": str(workspace_id),
            "cursor": rows[-1].cursor if rows else after_cursor,
            "changes": changes,
        }
