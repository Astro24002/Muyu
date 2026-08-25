from __future__ import annotations

from uuid import UUID

from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.db.models import Task


def search_tasks(session: Session, workspace_id: UUID, query: str, limit: int = 50) -> list[Task]:
    needle = f"%{query.strip()}%"
    return list(session.scalars(select(Task).where(Task.workspace_id == workspace_id, Task.deleted_at.is_(None), or_(Task.title.ilike(needle), Task.description.ilike(needle))).order_by(Task.updated_at.desc()).limit(min(100, max(1, limit)))))
