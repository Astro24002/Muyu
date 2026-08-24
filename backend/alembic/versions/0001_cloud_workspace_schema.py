"""Create the authoritative cloud workspace PostgreSQL schema.

This is intentionally a new root revision.  The previous password/P2P schema
is not upgraded in place; deployments provision an empty database instead.
"""

from collections.abc import Sequence

from alembic import op
from sqlalchemy import text

from app.db.models import Base


revision: str = "0001_cloud_workspace_schema"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    bind = op.get_bind()
    bind.execute(text("CREATE EXTENSION IF NOT EXISTS pg_trgm"))
    Base.metadata.create_all(bind=bind, checkfirst=True)

    # Partial indexes encode the active membership invariants directly in
    # PostgreSQL.  member_slot's CHECK constraint limits each workspace to
    # two active rows, while these indexes prevent duplicate occupancy.
    bind.execute(
        text(
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_users_normalized_phone "
            "ON users (phone)"
        )
    )
    bind.execute(
        text(
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_active_workspace_member_per_user "
            "ON workspace_memberships (user_id) WHERE status = 'ACTIVE'"
        )
    )
    bind.execute(
        text(
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_active_workspace_member_slot "
            "ON workspace_memberships (workspace_id, member_slot) WHERE status = 'ACTIVE'"
        )
    )
    bind.execute(
        text(
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_active_device_fingerprint "
            "ON android_devices (user_id, fingerprint) WHERE status <> 'REVOKED' AND fingerprint IS NOT NULL"
        )
    )
    bind.execute(
        text(
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_workspace_change_cursor "
            "ON workspace_change_log (workspace_id, cursor)"
        )
    )
    bind.execute(
        text(
            "CREATE INDEX IF NOT EXISTS ix_workspace_change_lookup "
            "ON workspace_change_log (workspace_id, cursor)"
        )
    )
    bind.execute(
        text(
            "CREATE INDEX IF NOT EXISTS ix_active_membership_workspace "
            "ON workspace_memberships (workspace_id) WHERE status = 'ACTIVE'"
        )
    )
    bind.execute(
        text(
            "CREATE INDEX IF NOT EXISTS ix_active_mobile_sessions "
            "ON mobile_sessions (user_id, device_id, expires_at) "
            "WHERE revoked_at IS NULL"
        )
    )
    bind.execute(
        text(
            "CREATE INDEX IF NOT EXISTS ix_unexpired_web_sessions "
            "ON web_sessions (user_id, expires_at) WHERE status = 'ACTIVE'"
        )
    )
    bind.execute(
        text(
            "CREATE INDEX IF NOT EXISTS ix_unexpired_challenges "
            "ON web_login_challenges (expires_at) WHERE status = 'PENDING'"
        )
    )
    bind.execute(
        text(
            "CREATE INDEX IF NOT EXISTS ix_tasks_workspace_list "
            "ON tasks (workspace_id, deleted_at, status, due_at)"
        )
    )
    # pg_trgm is database-scoped, while tests use isolated schemas.  Resolve
    # the installed operator class dynamically so a later schema can reuse
    # the extension without assuming it lives in that schema.
    bind.execute(
        text(
            """
            DO $$
            DECLARE trgm_schema text;
            BEGIN
                SELECT n.nspname INTO trgm_schema
                FROM pg_opclass c
                JOIN pg_namespace n ON n.oid = c.opcnamespace
                WHERE c.opcname = 'gin_trgm_ops'
                ORDER BY n.nspname
                LIMIT 1;
                IF trgm_schema IS NOT NULL THEN
                    EXECUTE format(
                        'CREATE INDEX IF NOT EXISTS ix_tasks_title_trgm ON tasks USING gin (title %I.gin_trgm_ops)',
                        trgm_schema
                    );
                END IF;
            END $$
            """
        )
    )
    bind.execute(
        text(
            "CREATE INDEX IF NOT EXISTS ix_task_comments_task "
            "ON task_comments (workspace_id, task_id, created_at)"
        )
    )
    bind.execute(
        text(
            "CREATE INDEX IF NOT EXISTS ix_activity_events_workspace "
            "ON activity_events (workspace_id, created_at)"
        )
    )

    # A regular CHECK constraint cannot inspect another table.  These
    # triggers make the Web-session approver invariant hold for direct SQL as
    # well as ORM writes.  Revoking a device immediately revokes its sessions.
    bind.execute(
        text(
            """
            CREATE OR REPLACE FUNCTION enforce_web_session_device_state()
            RETURNS trigger
            LANGUAGE plpgsql
            AS $$
            BEGIN
                IF TG_TABLE_NAME = 'web_sessions' AND NEW.status = 'ACTIVE' THEN
                    IF NOT EXISTS (
                        SELECT 1 FROM android_devices
                        WHERE id = NEW.approving_device_id AND status = 'ACTIVE'
                    ) THEN
                        RAISE EXCEPTION 'web session requires an active approving device'
                            USING ERRCODE = '23514';
                    END IF;
                ELSIF TG_TABLE_NAME = 'android_devices' AND NEW.status = 'REVOKED' THEN
                    UPDATE web_sessions
                    SET status = 'REVOKED', revoked_at = now(), updated_at = now()
                    WHERE approving_device_id = NEW.id AND status = 'ACTIVE';
                END IF;
                RETURN NEW;
            END;
            $$
            """
        )
    )
    bind.execute(text("DROP TRIGGER IF EXISTS trg_web_session_device_state ON web_sessions"))
    bind.execute(
        text(
            "CREATE TRIGGER trg_web_session_device_state "
            "BEFORE INSERT OR UPDATE OF status, approving_device_id ON web_sessions "
            "FOR EACH ROW EXECUTE FUNCTION enforce_web_session_device_state()"
        )
    )
    bind.execute(text("DROP TRIGGER IF EXISTS trg_android_device_state ON android_devices"))
    bind.execute(
        text(
            "CREATE TRIGGER trg_android_device_state "
            "AFTER UPDATE OF status ON android_devices "
            "FOR EACH ROW EXECUTE FUNCTION enforce_web_session_device_state()"
        )
    )


def downgrade() -> None:
    bind = op.get_bind()
    bind.execute(text("DROP TRIGGER IF EXISTS trg_android_device_state ON android_devices"))
    bind.execute(text("DROP TRIGGER IF EXISTS trg_web_session_device_state ON web_sessions"))
    bind.execute(text("DROP FUNCTION IF EXISTS enforce_web_session_device_state()"))
    Base.metadata.drop_all(bind=bind, checkfirst=True)
