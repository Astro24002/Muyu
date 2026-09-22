"""Persist the agreed completion criteria independently of review content."""

from collections.abc import Sequence

from alembic import op
from sqlalchemy import text


revision: str = "0017_task_acceptance_criteria"
down_revision: str | None = "0016_life_domains"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # Root metadata already includes this column on newly created databases.
    op.execute(text("ALTER TABLE tasks ADD COLUMN IF NOT EXISTS acceptance_criteria VARCHAR(500)"))


def downgrade() -> None:
    op.execute(text("ALTER TABLE tasks DROP COLUMN IF EXISTS acceptance_criteria"))
