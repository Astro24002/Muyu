"""Add lookup indexes used by workspace device and web-session cleanup."""

from collections.abc import Sequence

from alembic import op
from sqlalchemy import text


# Alembic's default version table uses VARCHAR(32); keep the identifier short
# even though the migration filename remains descriptive.
revision: str = "0002_device_session_indexes"
down_revision: str | None = "0001_cloud_workspace_schema"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


_WEB_SESSION_INDEX = "ix_web_sessions_status_expires_at"
_WEB_CHALLENGE_INDEX = "ix_web_login_challenges_status_expires_at"


def upgrade() -> None:
    # IF NOT EXISTS keeps this revision safe for databases where metadata
    # creation already materialized the declarative indexes from models.py.
    op.execute(
        text(
            "CREATE INDEX IF NOT EXISTS ix_web_sessions_status_expires_at "
            "ON web_sessions (status, expires_at)"
        )
    )
    op.execute(
        text(
            "CREATE INDEX IF NOT EXISTS ix_web_login_challenges_status_expires_at "
            "ON web_login_challenges (status, expires_at)"
        )
    )


def downgrade() -> None:
    op.execute(text(f"DROP INDEX IF EXISTS {_WEB_CHALLENGE_INDEX}"))
    op.execute(text(f"DROP INDEX IF EXISTS {_WEB_SESSION_INDEX}"))
