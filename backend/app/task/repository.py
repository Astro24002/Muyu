from __future__ import annotations

from uuid import UUID

from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session, selectinload

from app.task.models import Task, TaskAssignee, TaskUserPosition


class TaskRepository:
    def __init__(self, session: Session) -> None:
        self.session = session

    def get(self, task_id: UUID, *, include_deleted: bool = False) -> Task | None:
        statement = (
            select(Task)
            .options(selectinload(Task.assignees))
            .where(Task.id == task_id)
        )
        if not include_deleted:
            statement = statement.where(Task.deleted_at.is_(None))
        return self.session.scalar(statement)

    def list_tasks(self, user_id: UUID, *, parent_task_id: UUID | None = None) -> list[Task]:
        statement = (
            select(Task)
            .outerjoin(
                TaskUserPosition,
                (TaskUserPosition.task_id == Task.id) & (TaskUserPosition.user_id == user_id),
            )
            .options(selectinload(Task.assignees))
            .where(Task.deleted_at.is_(None), Task.parent_task_id == parent_task_id)
            .order_by(TaskUserPosition.position.asc().nulls_last(), Task.created_at.desc())
        )
        return list(self.session.scalars(statement).unique())

    def active_children(self, task_id: UUID) -> list[Task]:
        return list(
            self.session.scalars(
                select(Task).where(Task.parent_task_id == task_id, Task.deleted_at.is_(None))
            )
        )

    def next_position(self, user_id: UUID) -> int:
        current = self.session.scalar(
            select(func.max(TaskUserPosition.position)).where(TaskUserPosition.user_id == user_id)
        )
        return 0 if current is None else current + 1

    def set_position(self, user_id: UUID, task_id: UUID, position: int, updated_at) -> None:
        entry = self.session.get(TaskUserPosition, (user_id, task_id))
        if entry is None:
            self.session.add(
                TaskUserPosition(user_id=user_id, task_id=task_id, position=position, updated_at=updated_at)
            )
        else:
            entry.position = position
            entry.updated_at = updated_at

    def remove_position(self, user_id: UUID, task_id: UUID) -> None:
        self.session.execute(
            delete(TaskUserPosition).where(
                TaskUserPosition.user_id == user_id, TaskUserPosition.task_id == task_id
            )
        )

    def assignee_ids(self, task_id: UUID) -> set[UUID]:
        return set(
            self.session.scalars(
                select(TaskAssignee.user_id).where(TaskAssignee.task_id == task_id)
            )
        )
