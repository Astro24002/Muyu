"""Add task numbering and two-person task approval persistence."""

from collections.abc import Sequence

from alembic import op
from sqlalchemy import text


revision: str = "0003_two_person_task_approval"
down_revision: str | None = "0002_device_session_indexes"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _create_enum_types() -> None:
    op.execute(
        text(
            """
            DO $$
            BEGIN
                IF NOT EXISTS (
                    SELECT 1
                    FROM pg_type t
                    JOIN pg_namespace n ON n.oid = t.typnamespace
                    WHERE n.nspname = current_schema()
                      AND t.typname = 'task_quadrant'
                      AND t.typtype = 'e'
                ) THEN
                    CREATE TYPE task_quadrant AS ENUM ('Q1', 'Q2', 'Q3', 'Q4');
                END IF;
                IF NOT EXISTS (
                    SELECT 1
                    FROM pg_type t
                    JOIN pg_namespace n ON n.oid = t.typnamespace
                    WHERE n.nspname = current_schema()
                      AND t.typname = 'task_approval_request_type'
                      AND t.typtype = 'e'
                ) THEN
                    CREATE TYPE task_approval_request_type AS ENUM (
                        'TASK_UPDATE', 'QUADRANT_UPDATE', 'STATUS_UPDATE', 'TASK_DELETE',
                        'TASK_RESTORE', 'COMMENT_DELETE', 'ASSIGNEE_UPDATE', 'HANDLER_TRANSFER'
                    );
                END IF;
                IF NOT EXISTS (
                    SELECT 1
                    FROM pg_type t
                    JOIN pg_namespace n ON n.oid = t.typnamespace
                    WHERE n.nspname = current_schema()
                      AND t.typname = 'task_approval_request_status'
                      AND t.typtype = 'e'
                ) THEN
                    CREATE TYPE task_approval_request_status AS ENUM (
                        'PENDING', 'APPROVED', 'REJECTED', 'CONFLICTED', 'CANCELLED'
                    );
                END IF;
            END $$
            """
        )
    )


def _add_task_columns() -> None:
    op.execute(text("ALTER TABLE tasks ADD COLUMN IF NOT EXISTS task_number VARCHAR(8)"))
    op.execute(text("ALTER TABLE tasks ADD COLUMN IF NOT EXISTS quadrant task_quadrant"))
    op.execute(text("ALTER TABLE tasks ADD COLUMN IF NOT EXISTS progress INTEGER"))


def _add_comment_columns() -> None:
    op.execute(text("ALTER TABLE task_comments ADD COLUMN IF NOT EXISTS version INTEGER NOT NULL DEFAULT 1"))
    op.execute(text("ALTER TABLE task_comments ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ"))
    op.execute(text("ALTER TABLE task_comments ADD COLUMN IF NOT EXISTS deleted_by UUID"))
    op.execute(
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
                      AND r.relname = 'task_comments'
                      AND c.conname = 'fk_task_comments_deleted_by'
                ) THEN
                    ALTER TABLE task_comments
                        ADD CONSTRAINT fk_task_comments_deleted_by
                        FOREIGN KEY (deleted_by) REFERENCES users (id) ON DELETE RESTRICT;
                END IF;
            END $$
            """
        )
    )


def _create_number_sequence_table() -> None:
    op.execute(
        text(
            """
            CREATE TABLE IF NOT EXISTS task_number_sequences (
                period CHAR(4) PRIMARY KEY,
                next_value INTEGER NOT NULL DEFAULT 1
            )
            """
        )
    )


def _populate_task_numbers() -> None:
    # Legacy task rows have no number.  Number them deterministically within
    # each YYMM period before adding the NOT NULL and unique constraints.
    op.execute(
        text(
            """
            WITH numbered AS (
                SELECT
                    id,
                    to_char(created_at, 'YYMM') AS period,
                    row_number() OVER (
                        PARTITION BY to_char(created_at, 'YYMM')
                        ORDER BY created_at, id
                    ) AS sequence_value
                FROM tasks
                WHERE task_number IS NULL
            )
            UPDATE tasks AS task
            SET task_number = numbered.period || lpad(numbered.sequence_value::text, 4, '0')
            FROM numbered
            WHERE task.id = numbered.id
            """
        )
    )
    op.execute(
        text(
            """
            INSERT INTO task_number_sequences (period, next_value)
            SELECT left(task_number, 4), max(substring(task_number FROM 5)::integer) + 1
            FROM tasks
            WHERE task_number IS NOT NULL
            GROUP BY left(task_number, 4)
            ON CONFLICT (period) DO UPDATE
            SET next_value = GREATEST(task_number_sequences.next_value, EXCLUDED.next_value)
            """
        )
    )


def _create_approval_table() -> None:
    op.execute(
        text(
            """
            CREATE TABLE IF NOT EXISTS task_approval_requests (
                id UUID PRIMARY KEY,
                workspace_id UUID NOT NULL
                    CONSTRAINT fk_task_approval_requests_workspace_id
                    REFERENCES workspaces (id) ON DELETE CASCADE,
                task_id UUID NOT NULL
                    CONSTRAINT fk_task_approval_requests_task_id
                    REFERENCES tasks (id) ON DELETE RESTRICT,
                comment_id UUID
                    CONSTRAINT fk_task_approval_requests_comment_id
                    REFERENCES task_comments (id) ON DELETE RESTRICT,
                requester_id UUID NOT NULL
                    CONSTRAINT fk_task_approval_requests_requester_id
                    REFERENCES users (id) ON DELETE RESTRICT,
                approver_id UUID NOT NULL
                    CONSTRAINT fk_task_approval_requests_approver_id
                    REFERENCES users (id) ON DELETE RESTRICT,
                request_type task_approval_request_type NOT NULL,
                proposed_changes JSONB NOT NULL DEFAULT '{}'::jsonb,
                base_field_versions JSONB NOT NULL DEFAULT '{}'::jsonb,
                request_id UUID NOT NULL,
                status task_approval_request_status NOT NULL DEFAULT 'PENDING',
                created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                reviewed_at TIMESTAMPTZ,
                reviewed_by UUID
                    CONSTRAINT fk_task_approval_requests_reviewed_by
                    REFERENCES users (id) ON DELETE RESTRICT,
                rejection_reason TEXT,
                resolved_cursor INTEGER,
                CONSTRAINT uq_task_approval_workspace_request UNIQUE (workspace_id, request_id),
                CONSTRAINT ck_task_approval_requester_approver_distinct CHECK (requester_id <> approver_id)
            )
            """
        )
    )


def _add_approval_columns_and_constraints() -> None:
    # The table is new in this revision, but IF NOT EXISTS keeps a partially
    # applied deployment recoverable and supports schemas materialized by 0001.
    columns = (
        "id UUID",
        "workspace_id UUID",
        "task_id UUID",
        "comment_id UUID",
        "requester_id UUID",
        "approver_id UUID",
        "request_type task_approval_request_type",
        "proposed_changes JSONB NOT NULL DEFAULT '{}'::jsonb",
        "base_field_versions JSONB NOT NULL DEFAULT '{}'::jsonb",
        "request_id UUID",
        "status task_approval_request_status NOT NULL DEFAULT 'PENDING'",
        "created_at TIMESTAMPTZ NOT NULL DEFAULT now()",
        "reviewed_at TIMESTAMPTZ",
        "reviewed_by UUID",
        "rejection_reason TEXT",
        "resolved_cursor INTEGER",
    )
    for column in columns:
        name = column.split(" ", 1)[0]
        op.execute(text(f"ALTER TABLE task_approval_requests ADD COLUMN IF NOT EXISTS {name} {column[len(name) + 1:]}"))

    constraints = (
        """
        DO $$
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM pg_constraint c JOIN pg_class r ON r.oid = c.conrelid
                JOIN pg_namespace n ON n.oid = r.relnamespace
                WHERE n.nspname = current_schema() AND r.relname = 'task_approval_requests'
                  AND c.conname = 'fk_task_approval_requests_workspace_id'
            ) THEN
                ALTER TABLE task_approval_requests ADD CONSTRAINT fk_task_approval_requests_workspace_id
                    FOREIGN KEY (workspace_id) REFERENCES workspaces (id) ON DELETE CASCADE;
            END IF;
            IF NOT EXISTS (
                SELECT 1 FROM pg_constraint c JOIN pg_class r ON r.oid = c.conrelid
                JOIN pg_namespace n ON n.oid = r.relnamespace
                WHERE n.nspname = current_schema() AND r.relname = 'task_approval_requests'
                  AND c.conname = 'fk_task_approval_requests_task_id'
            ) THEN
                ALTER TABLE task_approval_requests ADD CONSTRAINT fk_task_approval_requests_task_id
                    FOREIGN KEY (task_id) REFERENCES tasks (id) ON DELETE RESTRICT;
            END IF;
            IF NOT EXISTS (
                SELECT 1 FROM pg_constraint c JOIN pg_class r ON r.oid = c.conrelid
                JOIN pg_namespace n ON n.oid = r.relnamespace
                WHERE n.nspname = current_schema() AND r.relname = 'task_approval_requests'
                  AND c.conname = 'fk_task_approval_requests_comment_id'
            ) THEN
                ALTER TABLE task_approval_requests ADD CONSTRAINT fk_task_approval_requests_comment_id
                    FOREIGN KEY (comment_id) REFERENCES task_comments (id) ON DELETE RESTRICT;
            END IF;
            IF NOT EXISTS (
                SELECT 1 FROM pg_constraint c JOIN pg_class r ON r.oid = c.conrelid
                JOIN pg_namespace n ON n.oid = r.relnamespace
                WHERE n.nspname = current_schema() AND r.relname = 'task_approval_requests'
                  AND c.conname = 'fk_task_approval_requests_requester_id'
            ) THEN
                ALTER TABLE task_approval_requests ADD CONSTRAINT fk_task_approval_requests_requester_id
                    FOREIGN KEY (requester_id) REFERENCES users (id) ON DELETE RESTRICT;
            END IF;
            IF NOT EXISTS (
                SELECT 1 FROM pg_constraint c JOIN pg_class r ON r.oid = c.conrelid
                JOIN pg_namespace n ON n.oid = r.relnamespace
                WHERE n.nspname = current_schema() AND r.relname = 'task_approval_requests'
                  AND c.conname = 'fk_task_approval_requests_approver_id'
            ) THEN
                ALTER TABLE task_approval_requests ADD CONSTRAINT fk_task_approval_requests_approver_id
                    FOREIGN KEY (approver_id) REFERENCES users (id) ON DELETE RESTRICT;
            END IF;
            IF NOT EXISTS (
                SELECT 1 FROM pg_constraint c JOIN pg_class r ON r.oid = c.conrelid
                JOIN pg_namespace n ON n.oid = r.relnamespace
                WHERE n.nspname = current_schema() AND r.relname = 'task_approval_requests'
                  AND c.conname = 'fk_task_approval_requests_reviewed_by'
            ) THEN
                ALTER TABLE task_approval_requests ADD CONSTRAINT fk_task_approval_requests_reviewed_by
                    FOREIGN KEY (reviewed_by) REFERENCES users (id) ON DELETE RESTRICT;
            END IF;
            IF NOT EXISTS (
                SELECT 1 FROM pg_constraint c JOIN pg_class r ON r.oid = c.conrelid
                JOIN pg_namespace n ON n.oid = r.relnamespace
                WHERE n.nspname = current_schema() AND r.relname = 'task_approval_requests'
                  AND c.conname = 'uq_task_approval_workspace_request'
            ) THEN
                ALTER TABLE task_approval_requests ADD CONSTRAINT uq_task_approval_workspace_request
                    UNIQUE (workspace_id, request_id);
            END IF;
            IF NOT EXISTS (
                SELECT 1 FROM pg_constraint c JOIN pg_class r ON r.oid = c.conrelid
                JOIN pg_namespace n ON n.oid = r.relnamespace
                WHERE n.nspname = current_schema() AND r.relname = 'task_approval_requests'
                  AND c.conname = 'ck_task_approval_requester_approver_distinct'
            ) THEN
                ALTER TABLE task_approval_requests ADD CONSTRAINT ck_task_approval_requester_approver_distinct
                    CHECK (requester_id <> approver_id);
            END IF;
        END $$
        """,
    )
    for constraint in constraints:
        op.execute(text(constraint))


def _create_indexes_and_task_constraints() -> None:
    op.execute(text("ALTER TABLE tasks ALTER COLUMN task_number SET NOT NULL"))
    op.execute(
        text(
            """
            DO $$
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM pg_constraint c JOIN pg_class r ON r.oid = c.conrelid
                    JOIN pg_namespace n ON n.oid = r.relnamespace
                    WHERE n.nspname = current_schema() AND r.relname = 'tasks'
                      AND c.conname = 'uq_tasks_task_number'
                ) THEN
                    ALTER TABLE tasks ADD CONSTRAINT uq_tasks_task_number UNIQUE (task_number);
                END IF;
                IF NOT EXISTS (
                    SELECT 1 FROM pg_constraint c JOIN pg_class r ON r.oid = c.conrelid
                    JOIN pg_namespace n ON n.oid = r.relnamespace
                    WHERE n.nspname = current_schema() AND r.relname = 'tasks'
                      AND c.conname = 'ck_tasks_progress_allowed'
                ) THEN
                    ALTER TABLE tasks ADD CONSTRAINT ck_tasks_progress_allowed
                        CHECK (progress IS NULL OR progress IN (20, 40, 60, 80));
                END IF;
            END $$
            """
        )
    )
    indexes = (
        "CREATE INDEX IF NOT EXISTS ix_task_approval_requests_workspace_status_approver "
        "ON task_approval_requests (workspace_id, status, approver_id)",
        "CREATE INDEX IF NOT EXISTS ix_task_approval_requests_workspace_status_requester "
        "ON task_approval_requests (workspace_id, status, requester_id)",
        "CREATE INDEX IF NOT EXISTS ix_task_approval_requests_task_status "
        "ON task_approval_requests (task_id, status)",
        "CREATE INDEX IF NOT EXISTS ix_task_approval_requests_comment_status "
        "ON task_approval_requests (comment_id, status)",
    )
    for statement in indexes:
        op.execute(text(statement))


def upgrade() -> None:
    _create_enum_types()
    _add_task_columns()
    _add_comment_columns()
    _create_number_sequence_table()
    _populate_task_numbers()
    _create_approval_table()
    _add_approval_columns_and_constraints()
    _create_indexes_and_task_constraints()


def downgrade() -> None:
    indexes = (
        "ix_task_approval_requests_comment_status",
        "ix_task_approval_requests_task_status",
        "ix_task_approval_requests_workspace_status_requester",
        "ix_task_approval_requests_workspace_status_approver",
    )
    for index in indexes:
        op.execute(text(f"DROP INDEX IF EXISTS {index}"))
    op.execute(text("DROP TABLE IF EXISTS task_approval_requests"))
    op.execute(text("DROP TABLE IF EXISTS task_number_sequences"))
    op.execute(text("ALTER TABLE task_comments DROP CONSTRAINT IF EXISTS fk_task_comments_deleted_by"))
    op.execute(text("ALTER TABLE task_comments DROP COLUMN IF EXISTS deleted_by"))
    op.execute(text("ALTER TABLE task_comments DROP COLUMN IF EXISTS deleted_at"))
    op.execute(text("ALTER TABLE task_comments DROP COLUMN IF EXISTS version"))
    op.execute(text("ALTER TABLE tasks DROP CONSTRAINT IF EXISTS ck_tasks_progress_allowed"))
    op.execute(text("ALTER TABLE tasks DROP CONSTRAINT IF EXISTS uq_tasks_task_number"))
    op.execute(text("ALTER TABLE tasks DROP COLUMN IF EXISTS progress"))
    op.execute(text("ALTER TABLE tasks DROP COLUMN IF EXISTS quadrant"))
    op.execute(text("ALTER TABLE tasks DROP COLUMN IF EXISTS task_number"))
    op.execute(text("DROP TYPE IF EXISTS task_approval_request_status"))
    op.execute(text("DROP TYPE IF EXISTS task_approval_request_type"))
    op.execute(text("DROP TYPE IF EXISTS task_quadrant"))
