from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.db.enums import MembershipStatus
from app.auth.profile import public_display_name
from app.db.models import Task, TaskApprovalRequest, TaskComment, TaskConflict, User, Workspace, WorkspaceChangeLog, WorkspaceClassification, WorkspaceCursor, WorkspaceMembership
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
        classifications = self.session.scalars(
            select(WorkspaceClassification)
            .where(WorkspaceClassification.workspace_id == workspace_id)
            .order_by(WorkspaceClassification.normalized_name.asc(), WorkspaceClassification.id.asc())
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
            "classifications": [
                {
                    "id": str(item.id),
                    "workspace_id": str(item.workspace_id),
                    "name": item.name,
                    "created_by": str(item.created_by),
                    "created_at": item.created_at.isoformat() if item.created_at else None,
                }
                for item in classifications
            ],
            "cursor": head,
        }

    def changes(self, workspace_id: UUID, after_cursor: int, limit: int = 100) -> dict[str, Any]:
        retention_cutoff = datetime.now(timezone.utc) - timedelta(days=max(1, int(self.retention_days)))
        oldest_retained = self.session.scalar(
            select(WorkspaceChangeLog.cursor)
            .where(
                WorkspaceChangeLog.workspace_id == workspace_id,
                WorkspaceChangeLog.created_at >= retention_cutoff,
            )
            .order_by(WorkspaceChangeLog.cursor.asc())
            .limit(1)
        )
        oldest_change = self.session.scalar(
            select(WorkspaceChangeLog.cursor)
            .where(WorkspaceChangeLog.workspace_id == workspace_id)
            .order_by(WorkspaceChangeLog.cursor.asc())
            .limit(1)
        )
        cursor_row = self.session.get(WorkspaceCursor, workspace_id)
        allocated_head = (cursor_row.next_cursor - 1) if cursor_row else 0
        logged_head = self.session.scalar(
            select(func.max(WorkspaceChangeLog.cursor)).where(
                WorkspaceChangeLog.workspace_id == workspace_id
            )
        ) or 0
        head = max(allocated_head, logged_head)

        if oldest_retained is None:
            # A workspace with only expired history cannot service an older pull.
            if oldest_change is not None and after_cursor < head:
                raise SyncCursorExpired("sync cursor expired")
        elif after_cursor < oldest_retained - 1:
            raise SyncCursorExpired("sync cursor expired")
        rows = self.session.scalars(select(WorkspaceChangeLog).where(WorkspaceChangeLog.workspace_id == workspace_id, WorkspaceChangeLog.cursor > after_cursor).order_by(WorkspaceChangeLog.cursor.asc()).limit(min(500, max(1, limit)))).all()
        expected_cursor = after_cursor + 1
        for item in rows:
            if item.cursor != expected_cursor:
                raise SyncCursorExpired("sync cursor expired")
            expected_cursor += 1
        if not rows and head > after_cursor:
            raise SyncCursorExpired("sync cursor expired")
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
            elif item.resource_type == "classification":
                classification = self.session.scalar(
                    select(WorkspaceClassification).where(
                        WorkspaceClassification.id == item.resource_id,
                        WorkspaceClassification.workspace_id == workspace_id,
                    )
                )
                if classification is not None:
                    resource = {
                        "id": str(classification.id),
                        "workspace_id": str(classification.workspace_id),
                        "name": classification.name,
                        "created_by": str(classification.created_by),
                        "created_at": classification.created_at.isoformat() if classification.created_at else None,
                    }
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
