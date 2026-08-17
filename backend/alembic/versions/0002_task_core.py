"""create task core tables

Revision ID: 0002_task_core
Revises: 0001_users_sessions
Create Date: 2026-08-17
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID


revision: str = "0002_task_core"
down_revision: str | None = "0001_users_sessions"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _uuid_column(name: str, *, primary_key: bool = False, nullable: bool = False) -> sa.Column:
    return sa.Column(name, UUID(as_uuid=True), primary_key=primary_key, nullable=nullable)


def _timestamp(name: str, *, nullable: bool = False) -> sa.Column:
    return sa.Column(name, sa.DateTime(timezone=True), nullable=nullable)


def upgrade() -> None:
    op.create_table(
        "tasks",
        _uuid_column("id", primary_key=True),
        sa.Column("parent_task_id", UUID(as_uuid=True), nullable=True),
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("description", sa.String(length=5000), nullable=False),
        sa.Column("status", sa.String(length=20), nullable=False, server_default="TODO"),
        sa.Column("current_handler_id", UUID(as_uuid=True), nullable=False),
        sa.Column("blocked_reason", sa.String(length=2000), nullable=True),
        _timestamp("blocked_since", nullable=True),
        sa.Column("resume_handler_id", UUID(as_uuid=True), nullable=True),
        sa.Column("waiting_for_user_id", UUID(as_uuid=True), nullable=True),
        _timestamp("planned_start_at", nullable=True),
        _timestamp("due_at", nullable=True),
        sa.Column("estimated_minutes", sa.Integer(), nullable=True),
        _timestamp("completed_at", nullable=True),
        sa.Column("created_by", UUID(as_uuid=True), nullable=False),
        sa.Column("recurring_task_id", UUID(as_uuid=True), nullable=True),
        sa.Column("version", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("status_version", sa.Integer(), nullable=False, server_default="1"),
        _timestamp("deleted_at", nullable=True),
        _timestamp("created_at"),
        _timestamp("updated_at"),
        sa.ForeignKeyConstraint(["parent_task_id"], ["tasks.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["current_handler_id"], ["users.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["resume_handler_id"], ["users.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["waiting_for_user_id"], ["users.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["created_by"], ["users.id"], ondelete="RESTRICT"),
    )
    op.create_index("ix_tasks_parent_task_id", "tasks", ["parent_task_id"])
    op.create_index("ix_tasks_status", "tasks", ["status"])
    op.create_index("ix_tasks_due_at", "tasks", ["due_at"])

    op.create_table(
        "task_assignees",
        sa.Column("task_id", UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", UUID(as_uuid=True), nullable=False),
        sa.ForeignKeyConstraint(["task_id"], ["tasks.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("task_id", "user_id"),
    )
    op.create_table(
        "task_user_positions",
        sa.Column("user_id", UUID(as_uuid=True), nullable=False),
        sa.Column("task_id", UUID(as_uuid=True), nullable=False),
        sa.Column("position", sa.Integer(), nullable=False),
        _timestamp("updated_at"),
        sa.ForeignKeyConstraint(["task_id"], ["tasks.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("user_id", "task_id"),
    )
    op.create_table(
        "task_status_history",
        _uuid_column("id", primary_key=True),
        sa.Column("task_id", UUID(as_uuid=True), nullable=False),
        sa.Column("from_status", sa.String(length=20), nullable=True),
        sa.Column("to_status", sa.String(length=20), nullable=False),
        sa.Column("changed_by", UUID(as_uuid=True), nullable=False),
        _timestamp("changed_at"),
        sa.ForeignKeyConstraint(["task_id"], ["tasks.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["changed_by"], ["users.id"], ondelete="RESTRICT"),
    )
    op.create_index("ix_task_status_history_task_id", "task_status_history", ["task_id"])
    op.create_table(
        "task_handler_history",
        _uuid_column("id", primary_key=True),
        sa.Column("task_id", UUID(as_uuid=True), nullable=False),
        sa.Column("from_user_id", UUID(as_uuid=True), nullable=True),
        sa.Column("to_user_id", UUID(as_uuid=True), nullable=False),
        sa.Column("changed_by", UUID(as_uuid=True), nullable=False),
        _timestamp("changed_at"),
        sa.ForeignKeyConstraint(["task_id"], ["tasks.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["from_user_id"], ["users.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["to_user_id"], ["users.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["changed_by"], ["users.id"], ondelete="RESTRICT"),
    )
    op.create_index("ix_task_handler_history_task_id", "task_handler_history", ["task_id"])
    op.create_table(
        "activity_events",
        _uuid_column("id", primary_key=True),
        sa.Column("actor_user_id", UUID(as_uuid=True), nullable=False),
        sa.Column("target_type", sa.String(length=50), nullable=False),
        sa.Column("target_id", UUID(as_uuid=True), nullable=False),
        sa.Column("action", sa.String(length=100), nullable=False),
        sa.Column("before_json", sa.JSON(), nullable=True),
        sa.Column("after_json", sa.JSON(), nullable=True),
        sa.Column("payload_json", sa.JSON(), nullable=False),
        sa.Column("aggregate_version", sa.Integer(), nullable=False),
        sa.Column("request_id", sa.String(length=100), nullable=True),
        _timestamp("created_at"),
        sa.ForeignKeyConstraint(["actor_user_id"], ["users.id"], ondelete="RESTRICT"),
    )
    op.create_index("ix_activity_events_target", "activity_events", ["target_type", "target_id"])


def downgrade() -> None:
    op.drop_index("ix_activity_events_target", table_name="activity_events")
    op.drop_table("activity_events")
    op.drop_index("ix_task_handler_history_task_id", table_name="task_handler_history")
    op.drop_table("task_handler_history")
    op.drop_index("ix_task_status_history_task_id", table_name="task_status_history")
    op.drop_table("task_status_history")
    op.drop_table("task_user_positions")
    op.drop_table("task_assignees")
    op.drop_index("ix_tasks_due_at", table_name="tasks")
    op.drop_index("ix_tasks_status", table_name="tasks")
    op.drop_index("ix_tasks_parent_task_id", table_name="tasks")
    op.drop_table("tasks")
