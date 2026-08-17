from __future__ import annotations

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.activity.models import ActivityEvent


class ActivityRepository:
    def __init__(self, session: Session) -> None:
        self.session = session

    def list_for_target(self, target_type: str, target_id: UUID) -> list[ActivityEvent]:
        return list(
            self.session.scalars(
                select(ActivityEvent)
                .where(ActivityEvent.target_type == target_type, ActivityEvent.target_id == target_id)
                .order_by(ActivityEvent.created_at.asc(), ActivityEvent.id.asc())
            )
        )
