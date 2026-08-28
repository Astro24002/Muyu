from __future__ import annotations

from datetime import datetime

from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from app.db.models import TaskNumberSequence


class TaskNumberAllocator:
    """Allocate immutable YYMMNNNN task numbers inside the current transaction."""

    def allocate(self, session: Session, at: datetime) -> str:
        period = at.strftime("%y%m")
        # The upsert locks the period row even when two devices create the
        # first task for a month concurrently.
        statement = (
            insert(TaskNumberSequence)
            .values(period=period, next_value=2)
            .on_conflict_do_update(
                index_elements=[TaskNumberSequence.period],
                set_={"next_value": TaskNumberSequence.next_value + 1},
            )
            .returning((TaskNumberSequence.next_value - 1).label("allocated_value"))
        )
        value = session.scalar(statement)
        if value is None:
            raise RuntimeError(f"unable to allocate task number for {period}")
        if value > 9999:
            raise ValueError(f"task number sequence exhausted for {period}")
        return f"{period}{value:04d}"
