"""Allow task invitations to exist before a task is created."""

from collections.abc import Sequence

from alembic import op
from sqlalchemy import text


revision: str = "0018_task_invitations"
down_revision: str | None = "0017_task_acceptance_criteria"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute(text("ALTER TYPE task_approval_request_type ADD VALUE IF NOT EXISTS 'TASK_INVITATION'"))


def downgrade() -> None:
    op.execute(text("""
        DO $$ BEGIN
          IF EXISTS (SELECT 1 FROM task_approval_requests WHERE request_type::text = 'TASK_INVITATION') THEN
            RAISE EXCEPTION 'resolve and archive task invitations before downgrading';
          END IF;
          CREATE TYPE task_approval_request_type_previous AS ENUM (
            'TASK_UPDATE', 'QUADRANT_UPDATE', 'STATUS_UPDATE', 'TASK_DELETE',
            'TASK_RESTORE', 'COMMENT_DELETE', 'HANDLER_TRANSFER', 'CLASSIFICATION_CREATE'
          );
          ALTER TABLE task_approval_requests ALTER COLUMN request_type
            TYPE task_approval_request_type_previous
            USING request_type::text::task_approval_request_type_previous;
          DROP TYPE task_approval_request_type;
          ALTER TYPE task_approval_request_type_previous RENAME TO task_approval_request_type;
        END $$
    """))
