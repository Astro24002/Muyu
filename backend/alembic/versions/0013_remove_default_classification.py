"""Remove the system-provisioned default task classification.

The ``默认`` classification was introduced as a convenience for early
workspaces, but new tasks must now explicitly select an approved
classification.  Existing tasks that only carried this system label remain
valid historical tasks and are converted to the legacy unclassified shape
before the classification row is removed.
"""

from collections.abc import Sequence

from alembic import op
from sqlalchemy import text


# Alembic's version table is VARCHAR(32); keep the identifier within that
# limit even though the file name carries the full description.
revision: str = "0013_remove_default_class"
down_revision: str | None = "0012_default_classification"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    bind = op.get_bind()

    # ``0010`` guarantees at most one label.  Clear only the system-provided
    # label; other historical unclassified tasks are left untouched.
    bind.execute(
        text(
            """
            UPDATE tasks
               SET labels = '[]'::jsonb
             WHERE jsonb_typeof(labels) = 'array'
               AND jsonb_array_length(labels) = 1
               AND btrim(labels ->> 0) = '默认'
            """
        )
    )
    bind.execute(
        text(
            """
            DELETE FROM workspace_classifications
             WHERE normalized_name = '默认'
            """
        )
    )


def downgrade() -> None:
    # The migration intentionally does not recreate a system classification or
    # restore task labels that were converted to the legacy empty shape.
    pass
