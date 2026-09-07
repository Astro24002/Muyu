"""Backfill approved classifications for legacy task labels.

The single-classification contract was introduced after tasks could already
contain labels.  Older databases therefore have valid task labels but no
corresponding rows in ``workspace_classifications``.  This revision creates
the missing rows without changing task data.
"""

from collections.abc import Sequence
from uuid import uuid4

from alembic import op
from sqlalchemy import text


revision: str = "0011_legacy_label_backfill"
down_revision: str | None = "0010_single_task_classification"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


MAX_CLASSIFICATION_LENGTH = 5


def _normalize_legacy_label(value: object) -> tuple[str, str] | None:
    """Return the production classification spelling/key for a valid label."""
    if not isinstance(value, str):
        return None
    name = value.strip()
    if not name or len(name) > MAX_CLASSIFICATION_LENGTH:
        return None
    normalized = name.casefold()
    if len(normalized) > MAX_CLASSIFICATION_LENGTH:
        return None
    return name, normalized


def upgrade() -> None:
    bind = op.get_bind()

    # Pick the earliest task for each workspace/key before inserting anything.
    # Python performs casefolding here because PostgreSQL lower() is not the
    # same operation for all Unicode input (for example, ``ß``).
    candidates: dict[tuple[object, str], tuple[str, object, object]] = {}
    rows = bind.execute(
        text(
            """
            SELECT workspace_id,
                   created_by,
                   created_at,
                   labels ->> 0 AS label
              FROM tasks
             WHERE jsonb_typeof(labels) = 'array'
               AND jsonb_array_length(labels) = 1
               AND jsonb_typeof(labels -> 0) = 'string'
             ORDER BY workspace_id, created_at ASC NULLS LAST, id
            """
        )
    )
    for row in rows:
        normalized_label = _normalize_legacy_label(row.label)
        if normalized_label is None:
            continue
        name, normalized_name = normalized_label
        key = (row.workspace_id, normalized_name)
        candidates.setdefault(key, (name, row.created_by, row.created_at))

    existing = {
        (row.workspace_id, row.normalized_name)
        for row in bind.execute(
            text(
                """
                SELECT workspace_id, normalized_name
                  FROM workspace_classifications
                """
            )
        )
    }

    for (workspace_id, normalized_name), (name, created_by, created_at) in candidates.items():
        if (workspace_id, normalized_name) in existing:
            continue
        bind.execute(
            text(
                """
                INSERT INTO workspace_classifications
                    (id, workspace_id, name, normalized_name, created_by, created_at)
                VALUES
                    (:id, :workspace_id, :name, :normalized_name, :created_by, :created_at)
                ON CONFLICT (workspace_id, normalized_name) DO NOTHING
                """
            ),
            {
                "id": uuid4(),
                "workspace_id": workspace_id,
                "name": name,
                "normalized_name": normalized_name,
                "created_by": created_by,
                "created_at": created_at,
            },
        )
        # This also makes the loop deterministic if a concurrent writer wins
        # the ON CONFLICT race while an instance is being upgraded.
        existing.add((workspace_id, normalized_name))


def downgrade() -> None:
    # The rows may have been used by tasks after this migration. Removing them
    # would make those tasks unreadable, so the backfill is intentionally kept.
    pass
