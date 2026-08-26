from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.enums import MembershipStatus
from app.db.models import Task, TaskConflict, Workspace, WorkspaceChangeLog, WorkspaceCursor, WorkspaceMembership
from app.tasks.service import TaskService


class SyncCursorExpired(Exception):
    pass


class SyncService:
    def __init__(self, session: Session, *, retention_days: int = 30) -> None:
        self.session = session
        self.retention_days = retention_days

    def snapshot(self, workspace_id: UUID) -> dict[str, Any]:
        workspace = self.session.get(Workspace, workspace_id)
        if workspace is None:
            raise ValueError("workspace not found")
        memberships = self.session.scalars(select(WorkspaceMembership).where(WorkspaceMembership.workspace_id == workspace_id, WorkspaceMembership.status == MembershipStatus.ACTIVE)).all()
        tasks = self.session.scalars(select(Task).where(Task.workspace_id == workspace_id, Task.deleted_at.is_(None)).order_by(Task.updated_at.desc())).all()
        conflicts = self.session.scalars(select(TaskConflict).where(TaskConflict.workspace_id == workspace_id, TaskConflict.status == "OPEN")).all()
        cursor_row = self.session.get(WorkspaceCursor, workspace_id)
        head = max(0, (cursor_row.next_cursor - 1) if cursor_row else 0)
        # Keep task-derived fields identical across sync and HTTP responses.
        service = TaskService(self.session)
        task_snapshots = [service.snapshot(task) for task in tasks]
        return {
            "workspace_id": str(workspace_id),
            "workspace": {"id": str(workspace.id), "name": workspace.name, "status": workspace.status.value},
            "members": [{"user_id": str(item.user_id), "member_slot": item.member_slot} for item in memberships],
            "tasks": task_snapshots,
            "conflicts": [{"id": str(item.id), "task_id": str(item.task_id), "field": item.target, "status": item.status.value} for item in conflicts],
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
                task = self.session.get(Task, item.resource_id)
                if task is not None:
                    resource = TaskService(self.session).snapshot(task)
            changes.append({"cursor": item.cursor, "resource_type": item.resource_type, "resource_id": str(item.resource_id), "action": item.action.value, "operation_id": str(item.operation_id) if item.operation_id else None, "resource": resource})
        return {
            "workspace_id": str(workspace_id),
            "cursor": rows[-1].cursor if rows else after_cursor,
            "changes": changes,
        }
