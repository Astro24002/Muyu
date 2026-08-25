from __future__ import annotations

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.models import ActivityEvent


def list_security_events(session: Session, workspace_id: UUID, limit: int = 100) -> list[ActivityEvent]:
    return list(
        session.scalars(
            select(ActivityEvent)
            .where(ActivityEvent.workspace_id == workspace_id)
            .order_by(ActivityEvent.created_at.desc())
            .limit(min(100, max(1, limit)))
        )
    )
