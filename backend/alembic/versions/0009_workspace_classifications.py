"""Add approved workspace classifications and classification approvals."""

from collections.abc import Sequence

from alembic import op
from sqlalchemy import text


revision: str = "0009_workspace_classifications"
down_revision: str | None = "0008_default_task_due_at"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _add_approval_enum_value() -> None:
    op.execute(
        text(
            """
            DO $$
            BEGIN
                IF NOT EXISTS (
                    SELECT 1
                    FROM pg_enum item
                    JOIN pg_type type ON type.oid = item.enumtypid
                    JOIN pg_namespace namespace ON namespace.oid = type.typnamespace
                    WHERE namespace.nspname = current_schema()
                      AND type.typname = 'task_approval_request_type'
                      AND item.enumlabel = 'CLASSIFICATION_CREATE'
                ) THEN
                    ALTER TYPE task_approval_request_type
                        ADD VALUE 'CLASSIFICATION_CREATE';
                END IF;
            END $$
            """
        )
    )


def _make_classification_table() -> None:
    op.execute(
        text(
            """
            CREATE TABLE IF NOT EXISTS workspace_classifications (
                id UUID PRIMARY KEY NOT NULL,
                workspace_id UUID NOT NULL REFERENCES workspaces (id) ON DELETE CASCADE,
                name VARCHAR(5) NOT NULL,
                normalized_name VARCHAR(5) NOT NULL,
                created_by UUID NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
                created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                CONSTRAINT uq_workspace_classifications_normalized_name
                    UNIQUE (workspace_id, normalized_name)
            )
            """
        )
    )
    op.execute(
        text(
            """
            CREATE INDEX IF NOT EXISTS ix_workspace_classifications_workspace
                ON workspace_classifications (workspace_id, normalized_name)
            """
        )
    )


def upgrade() -> None:
    _add_approval_enum_value()
    _make_classification_table()
    op.alter_column("task_operations", "task_id", nullable=True)
    op.alter_column("task_approval_requests", "task_id", nullable=True)


def downgrade() -> None:
    # The table and enum value are intentionally retained by downgrade because
    # PostgreSQL cannot remove an enum value safely while preserving approvals.
    pass
