"""Collapse legacy multi-label tasks to the single classification contract."""

from collections.abc import Sequence

from alembic import op
from sqlalchemy import text


revision: str = "0010_single_task_classification"
down_revision: str | None = "0009_workspace_classifications"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # ``labels`` remains an array on the wire, so retain the first historical
    # value while removing the obsolete multi-classification shape. Empty
    # legacy arrays are kept readable and are rejected on all new writes.
    op.execute(
        text(
            """
            UPDATE tasks
               SET labels = jsonb_build_array(labels -> 0)
             WHERE jsonb_typeof(labels) = 'array'
               AND jsonb_array_length(labels) > 1
            """
        )
    )
    op.execute(
        text(
            """
            DO $$
            BEGIN
                IF NOT EXISTS (
                    SELECT 1
                      FROM pg_constraint
                     WHERE conname = 'ck_tasks_single_classification'
                       AND conrelid = 'tasks'::regclass
                ) THEN
                    ALTER TABLE tasks
                        ADD CONSTRAINT ck_tasks_single_classification
                        CHECK (jsonb_array_length(labels) <= 1);
                END IF;
            END $$
            """
        )
    )


def downgrade() -> None:
    # The collapsed values cannot be reconstructed. Keep the invariant in
    # place rather than reintroducing a shape the clients no longer support.
    pass
