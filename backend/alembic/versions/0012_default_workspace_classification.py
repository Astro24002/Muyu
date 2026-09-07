"""Provision the system ``默认`` classification for every eligible workspace."""

from collections.abc import Sequence
from uuid import uuid4

from alembic import op
from sqlalchemy import text


revision: str = "0012_default_classification"
down_revision: str | None = "0011_legacy_label_backfill"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    bind = op.get_bind()
    existing = {
        row.workspace_id
        for row in bind.execute(
            text(
                """
                SELECT workspace_id
                  FROM workspace_classifications
                 WHERE normalized_name = '默认'
                """
            )
        )
    }

    # A workspace can be created before its partner joins.  The first active
    # member is therefore the only valid creator for the system row; workspaces
    # without one are left untouched and can be picked up safely by a later run.
    members = bind.execute(
        text(
            """
            SELECT DISTINCT ON (workspace_id) workspace_id, user_id
              FROM workspace_memberships
             WHERE status = 'ACTIVE'
             ORDER BY workspace_id, member_slot, created_at, id
            """
        )
    )
    for row in members:
        if row.workspace_id in existing:
            continue
        bind.execute(
            text(
                """
                INSERT INTO workspace_classifications
                    (id, workspace_id, name, normalized_name, created_by)
                VALUES
                    (:id, :workspace_id, '默认', '默认', :created_by)
                ON CONFLICT (workspace_id, normalized_name) DO NOTHING
                """
            ),
            {
                "id": uuid4(),
                "workspace_id": row.workspace_id,
                "created_by": row.user_id,
            },
        )
        existing.add(row.workspace_id)


def downgrade() -> None:
    # The system row may already be referenced by tasks, so it is intentionally
    # retained during downgrade.
    pass
