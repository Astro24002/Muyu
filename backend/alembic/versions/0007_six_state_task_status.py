"""Migrate tasks to the canonical six-state status model."""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql


revision: str = "0007_six_state_task_status"
down_revision: str | None = "0006_trust_sms_devices"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


_LEGACY_STATUSES = ("TODO", "IN_PROGRESS", "WAITING", "COMPLETED", "CANCELLED")
_CANONICAL_STATUSES = ("TODO", "IN_PROGRESS", "BLOCKED", "REVIEW", "DONE", "CANCELLED")
_LEGACY_TO_CANONICAL = {"WAITING": "BLOCKED", "COMPLETED": "DONE"}
_CANONICAL_TO_LEGACY = {"BLOCKED": "WAITING", "REVIEW": "IN_PROGRESS", "DONE": "COMPLETED"}


def _enum_values(bind: sa.Connection) -> list[str]:
    return list(
        bind.scalars(
            sa.text(
                """
                SELECT e.enumlabel
                FROM pg_type t
                JOIN pg_enum e ON e.enumtypid = t.oid
                JOIN pg_namespace n ON n.oid = t.typnamespace
                WHERE n.nspname = current_schema() AND t.typname = 'task_status'
                ORDER BY e.enumsortorder
                """
            )
        )
    )


def _alter_status_columns(type_sql: str) -> None:
    using_cast = "text" if type_sql == "TEXT" else type_sql
    for table_name, column_name in (
        ("tasks", "status"),
        ("task_status_history", "from_status"),
        ("task_status_history", "to_status"),
    ):
        op.execute(
            sa.text(
                f"ALTER TABLE {table_name} ALTER COLUMN {column_name} "
                f"TYPE {type_sql} USING {column_name}::{using_cast}"
            )
        )


def _replace_task_status_enum(bind: sa.Connection, labels: Sequence[str], replacements: dict[str, str]) -> None:
    if _enum_values(bind) == list(labels):
        return

    op.alter_column("tasks", "status", server_default=None)
    _alter_status_columns("TEXT")

    tasks = sa.table("tasks", sa.column("status", sa.Text()))
    history = sa.table(
        "task_status_history",
        sa.column("from_status", sa.Text()),
        sa.column("to_status", sa.Text()),
    )
    for old_status, new_status in replacements.items():
        bind.execute(
            sa.update(tasks)
            .where(tasks.c.status == old_status)
            .values(status=new_status)
        )
        for column in (history.c.from_status, history.c.to_status):
            bind.execute(
                sa.update(history)
                .where(column == old_status)
                .values({column.name: new_status})
            )

    enum_labels = ", ".join(f"'{label}'" for label in labels)
    op.execute(sa.text(f"CREATE TYPE task_status_replacement AS ENUM ({enum_labels})"))
    op.execute(sa.text("DROP TYPE task_status"))
    op.execute(sa.text("ALTER TYPE task_status_replacement RENAME TO task_status"))
    _alter_status_columns("task_status")
    op.alter_column("tasks", "status", server_default="TODO")


def _column_exists(bind: sa.Connection, column_name: str) -> bool:
    return bool(
        bind.scalar(
            sa.text(
                """
                SELECT 1
                FROM information_schema.columns
                WHERE table_schema = current_schema()
                  AND table_name = 'tasks'
                  AND column_name = :column_name
                """
            ),
            {"column_name": column_name},
        )
    )


def _reviewer_foreign_key(bind: sa.Connection) -> str | None:
    return bind.scalar(
        sa.text(
            """
            SELECT c.conname
            FROM pg_constraint c
            JOIN pg_class table_constraint ON table_constraint.oid = c.conrelid
            JOIN pg_namespace table_schema ON table_schema.oid = table_constraint.relnamespace
            JOIN pg_class referenced_table ON referenced_table.oid = c.confrelid
            JOIN pg_attribute constrained_column
              ON constrained_column.attrelid = c.conrelid
             AND constrained_column.attnum = ANY(c.conkey)
            WHERE c.contype = 'f'
              AND table_schema.nspname = current_schema()
              AND table_constraint.relname = 'tasks'
              AND referenced_table.relname = 'users'
              AND constrained_column.attname = 'reviewer_user_id'
            """
        )
    )


def _add_review_columns(bind: sa.Connection) -> None:
    columns = (
        sa.Column("reviewer_user_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("review_submitted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("reviewed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("review_rejection_reason", sa.Text(), nullable=True),
    )
    for column in columns:
        if not _column_exists(bind, column.name):
            op.add_column("tasks", column)

    if _reviewer_foreign_key(bind) is None:
        op.create_foreign_key(
            "fk_tasks_reviewer_user_id",
            "tasks",
            "users",
            ["reviewer_user_id"],
            ["id"],
            ondelete="RESTRICT",
        )


def _drop_review_columns(bind: sa.Connection) -> None:
    reviewer_foreign_key = _reviewer_foreign_key(bind)
    if reviewer_foreign_key is not None:
        op.drop_constraint(reviewer_foreign_key, "tasks", type_="foreignkey")
    for column_name in (
        "review_rejection_reason",
        "reviewed_at",
        "review_submitted_at",
        "reviewer_user_id",
    ):
        if _column_exists(bind, column_name):
            op.drop_column("tasks", column_name)


def upgrade() -> None:
    bind = op.get_bind()
    if _enum_values(bind) != list(_CANONICAL_STATUSES):
        _replace_task_status_enum(bind, _CANONICAL_STATUSES, _LEGACY_TO_CANONICAL)
    _add_review_columns(bind)


def downgrade() -> None:
    bind = op.get_bind()
    _drop_review_columns(bind)
    if _enum_values(bind) != list(_LEGACY_STATUSES):
        _replace_task_status_enum(bind, _LEGACY_STATUSES, _CANONICAL_TO_LEGACY)
