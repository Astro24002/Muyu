"""Add the user-authored next-step text to tasks."""

from collections.abc import Sequence

from alembic import op
from sqlalchemy import text


revision: str = "0015_task_next_step_text"
down_revision: str | None = "0014_moment_home_indexes"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # The root revision creates tables from the current ORM metadata for a
    # clean database, so this revision must also be safe when that column was
    # already present during a fresh upgrade.
    op.execute(
        text(
            "ALTER TABLE tasks ADD COLUMN IF NOT EXISTS "
            "next_step_text VARCHAR(90)"
        )
    )


def downgrade() -> None:
    op.execute(text("ALTER TABLE tasks DROP COLUMN IF EXISTS next_step_text"))
