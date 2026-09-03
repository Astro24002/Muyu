"""Backfill missing task deadlines using the creation time plus two weeks.

New task writes apply the same rule in ``TaskService``.  This migration only
touches legacy rows without a deadline; an explicitly chosen deadline is
preserved.  The column remains nullable so old integrations can still be
read safely while they are upgraded.
"""

from collections.abc import Sequence

from alembic import op
from sqlalchemy import text


revision: str = "0008_default_task_due_at"
down_revision: str | None = "0007_six_state_task_status"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute(
        text(
            """
            UPDATE tasks
               SET due_at = created_at + INTERVAL '14 days'
             WHERE due_at IS NULL
               AND created_at IS NOT NULL
            """
        )
    )


def downgrade() -> None:
    # The original null rows cannot be identified after the backfill without
    # an additional audit column, so the data-preserving downgrade is a no-op.
    pass
