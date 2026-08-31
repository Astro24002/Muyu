"""Require a quadrant and persist task classification labels."""

from collections.abc import Sequence

from alembic import op
from sqlalchemy import text


revision: str = "0004_task_labels_quadrant"
down_revision: str | None = "0003_two_person_task_approval"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    bind = op.get_bind()

    # A missing quadrant is a data-quality decision, not a migration default.
    # Fail loudly so an operator can reset the development database or assign
    # each task deliberately before making the constraint mandatory.
    missing_quadrants = bind.execute(
        text("SELECT count(*) FROM tasks WHERE quadrant IS NULL")
    ).scalar_one()
    if missing_quadrants:
        raise RuntimeError(
            "cannot make tasks.quadrant required: "
            f"{missing_quadrants} task rows have no quadrant"
        )

    bind.execute(
        text(
            "ALTER TABLE tasks ADD COLUMN IF NOT EXISTS labels "
            "JSONB NOT NULL DEFAULT '[]'::jsonb"
        )
    )
    bind.execute(text("UPDATE tasks SET labels = '[]'::jsonb WHERE labels IS NULL"))
    bind.execute(text("ALTER TABLE tasks ALTER COLUMN labels SET DEFAULT '[]'::jsonb"))
    bind.execute(text("ALTER TABLE tasks ALTER COLUMN labels SET NOT NULL"))
    bind.execute(text("ALTER TABLE tasks ALTER COLUMN quadrant SET NOT NULL"))
    bind.execute(
        text(
            """
            DO $$
            BEGIN
                IF NOT EXISTS (
                    SELECT 1
                    FROM pg_constraint c
                    JOIN pg_class r ON r.oid = c.conrelid
                    JOIN pg_namespace n ON n.oid = r.relnamespace
                    WHERE n.nspname = current_schema()
                      AND r.relname = 'tasks'
                      AND c.conname = 'ck_tasks_labels_array'
                ) THEN
                    ALTER TABLE tasks ADD CONSTRAINT ck_tasks_labels_array
                        CHECK (jsonb_typeof(labels) = 'array');
                END IF;
            END $$
            """
        )
    )


def downgrade() -> None:
    bind = op.get_bind()
    bind.execute(text("ALTER TABLE tasks DROP CONSTRAINT IF EXISTS ck_tasks_labels_array"))
    bind.execute(text("ALTER TABLE tasks DROP COLUMN IF EXISTS labels"))
    bind.execute(text("ALTER TABLE tasks ALTER COLUMN quadrant DROP NOT NULL"))
