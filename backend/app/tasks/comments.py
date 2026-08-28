from __future__ import annotations

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.models import TaskComment
from app.tasks.service import TaskService


def add_comment(session: Session, workspace_id: UUID, actor_user_id: UUID, task_id: UUID, body: str, request_id: UUID | None = None) -> TaskComment:
    return TaskService(session).add_comment(workspace_id, actor_user_id, task_id, body, request_id)


def list_comments(session: Session, workspace_id: UUID, task_id: UUID) -> list[TaskComment]:
    return list(session.scalars(select(TaskComment).where(TaskComment.workspace_id == workspace_id, TaskComment.task_id == task_id).order_by(TaskComment.created_at)))


def delete_comment(session: Session, workspace_id: UUID, actor_user_id: UUID, comment_id: UUID, request_id: UUID, base_version: int) -> TaskComment:
    return TaskService(session).delete_comment(workspace_id, actor_user_id, comment_id, request_id, base_version)
