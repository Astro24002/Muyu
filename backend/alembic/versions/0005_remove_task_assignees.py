"""Remove task participants and retire the assignee approval request type.

The downgrade restores only the old database shape for migration tooling. It
cannot restore participant rows removed by the upgrade.
"""

from collections.abc import Sequence

from alembic import op
from sqlalchemy import text


revision: str = "0005_remove_task_assignees"
down_revision: str | None = "0004_task_labels_quadrant"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _validate_current_handlers() -> None:
    bind = op.get_bind()
    invalid_tasks = bind.execute(
        text(
            """
            SELECT task.id,
                   CASE
                       WHEN task.current_handler_id IS NULL
                           THEN 'null current_handler_id'
                       ELSE 'current_handler_id is not an ACTIVE member of the same workspace'
                   END AS reason
            FROM tasks AS task
            LEFT JOIN workspace_memberships AS membership
              ON membership.workspace_id = task.workspace_id
             AND membership.user_id = task.current_handler_id
             AND membership.status = 'ACTIVE'
            WHERE task.deleted_at IS NULL
              AND (task.current_handler_id IS NULL OR membership.user_id IS NULL)
            ORDER BY task.id
            """
        )
    ).all()
    if invalid_tasks:
        details = ", ".join(f"{row.id} ({row.reason})" for row in invalid_tasks)
        raise RuntimeError(
            "cannot remove task participants: every non-deleted task must have "
            "a current_handler_id that is an ACTIVE member of the same workspace; "
            f"invalid task rows: {details}"
        )


def _replace_approval_request_type(labels: str) -> None:
    bind = op.get_bind()
    bind.execute(text(f"CREATE TYPE task_approval_request_type_replacement AS ENUM ({labels})"))
    bind.execute(
        text(
            "ALTER TABLE task_approval_requests "
            "ALTER COLUMN request_type TYPE TEXT "
            "USING request_type::text"
        )
    )
    bind.execute(text("DROP TYPE task_approval_request_type"))
    bind.execute(
        text(
            "ALTER TYPE task_approval_request_type_replacement "
            "RENAME TO task_approval_request_type"
        )
    )
    bind.execute(
        text(
            "ALTER TABLE task_approval_requests "
            "ALTER COLUMN request_type TYPE task_approval_request_type "
            "USING request_type::task_approval_request_type"
        )
    )


def upgrade() -> None:
    _validate_current_handlers()

    bind = op.get_bind()
    bind.execute(
        text(
            "DELETE FROM task_approval_requests "
            "WHERE request_type::text = 'ASSIGNEE_UPDATE'"
        )
    )
    _replace_approval_request_type(
        "'TASK_UPDATE', 'QUADRANT_UPDATE', 'STATUS_UPDATE', 'TASK_DELETE', "
        "'TASK_RESTORE', 'COMMENT_DELETE', 'HANDLER_TRANSFER'"
    )
    bind.execute(text("DROP TABLE IF EXISTS task_assignees CASCADE"))


def downgrade() -> None:
    # This restores migration-tooling schema shape only; participant data
    # deleted by upgrade is intentionally not fabricated or recovered.
    _replace_approval_request_type(
        "'TASK_UPDATE', 'QUADRANT_UPDATE', 'STATUS_UPDATE', 'TASK_DELETE', "
        "'TASK_RESTORE', 'COMMENT_DELETE', 'ASSIGNEE_UPDATE', 'HANDLER_TRANSFER'"
    )
    bind = op.get_bind()
    bind.execute(
        text(
            """
            CREATE TABLE IF NOT EXISTS task_assignees (
                task_id UUID NOT NULL REFERENCES tasks (id) ON DELETE CASCADE,
                user_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
                PRIMARY KEY (task_id, user_id)
            )
            """
        )
    )
