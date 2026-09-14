"""Add lookup indexes for the action-first home projection."""

from collections.abc import Sequence

from alembic import op
from sqlalchemy import text


revision: str = "0014_moment_home_indexes"
down_revision: str | None = "0013_remove_default_class"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


_INDEXES = (
    (
        "ix_tasks_home_current_handler",
        "CREATE INDEX IF NOT EXISTS ix_tasks_home_current_handler "
        "ON tasks (workspace_id, deleted_at, status, current_handler_id, due_at)",
    ),
    (
        "ix_tasks_home_reviewer",
        "CREATE INDEX IF NOT EXISTS ix_tasks_home_reviewer "
        "ON tasks (workspace_id, deleted_at, status, reviewer_user_id, due_at)",
    ),
)


def upgrade() -> None:
    for _, statement in _INDEXES:
        op.execute(text(statement))


def downgrade() -> None:
    for name, _ in reversed(_INDEXES):
        op.execute(text(f"DROP INDEX IF EXISTS {name}"))
