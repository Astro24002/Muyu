from __future__ import annotations

from typing import Generic, TypeVar
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from app.db.models import WorkspaceCursor


ModelT = TypeVar("ModelT")


class Repository(Generic[ModelT]):
    """Small persistence boundary; callers own transaction commit/rollback."""

    def __init__(self, session: Session) -> None:
        self.session = session

    def add(self, entity: ModelT) -> ModelT:
        self.session.add(entity)
        self.session.flush()
        return entity

    def get(self, model: type[ModelT], entity_id: UUID) -> ModelT | None:
        return self.session.get(model, entity_id)

    def allocate_workspace_cursor(self, workspace_id: UUID) -> int:
        self.session.execute(
            insert(WorkspaceCursor)
            .values(workspace_id=workspace_id, next_cursor=1)
            .on_conflict_do_nothing(index_elements=[WorkspaceCursor.workspace_id])
        )
        row = self.session.scalar(
            select(WorkspaceCursor).where(WorkspaceCursor.workspace_id == workspace_id).with_for_update()
        )
        if row is None:  # pragma: no cover - protected by the upsert above
            raise RuntimeError("workspace cursor row could not be created")
        cursor = row.next_cursor
        row.next_cursor += 1
        self.session.flush()
        return cursor


class WorkspaceCursorRepository(Repository[WorkspaceCursor]):
    def allocate(self, workspace_id: UUID) -> int:
        return self.allocate_workspace_cursor(workspace_id)
