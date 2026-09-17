"""Add the independent ledger, habit, check-in and anniversary domains."""

from collections.abc import Sequence

from alembic import op
from sqlalchemy import text


revision: str = "0016_life_domains"
down_revision: str | None = "0015_task_next_step_text"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    bind = op.get_bind()
    # The root revision creates current ORM metadata for a clean database, so
    # every statement here is idempotent for both a fresh and an existing DB.
    bind.execute(
        text(
            """
            ALTER TABLE tasks ADD COLUMN IF NOT EXISTS source_key VARCHAR(255);
            CREATE UNIQUE INDEX IF NOT EXISTS uq_tasks_workspace_source_key
              ON tasks (workspace_id, source_key)
              WHERE source_key IS NOT NULL;

            DO $$ BEGIN
              CREATE TYPE ledger_entry_type AS ENUM ('EXPENSE', 'INCOME');
            EXCEPTION WHEN duplicate_object THEN NULL; END $$;
            DO $$ BEGIN
              CREATE TYPE habit_frequency AS ENUM ('DAILY', 'WEEKLY', 'MONTHLY');
            EXCEPTION WHEN duplicate_object THEN NULL; END $$;
            DO $$ BEGIN
              CREATE TYPE habit_status AS ENUM ('ACTIVE', 'PAUSED', 'DELETED');
            EXCEPTION WHEN duplicate_object THEN NULL; END $$;
            DO $$ BEGIN
              CREATE TYPE anniversary_kind AS ENUM ('ANNIVERSARY', 'BIRTHDAY', 'IMPORTANT_DAY');
            EXCEPTION WHEN duplicate_object THEN NULL; END $$;

            CREATE TABLE IF NOT EXISTS domain_commands (
              id UUID PRIMARY KEY,
              workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
              request_id UUID NOT NULL,
              actor_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
              resource_type VARCHAR(64) NOT NULL,
              resource_id UUID NOT NULL,
              fingerprint VARCHAR(128) NOT NULL,
              cursor INTEGER NOT NULL,
              created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
              CONSTRAINT uq_domain_commands_workspace_request UNIQUE (workspace_id, request_id)
            );

            CREATE TABLE IF NOT EXISTS ledger_entries (
              id UUID PRIMARY KEY,
              workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
              type ledger_entry_type NOT NULL,
              amount_minor INTEGER NOT NULL,
              currency VARCHAR(3) NOT NULL DEFAULT 'CNY',
              title VARCHAR(200) NOT NULL,
              category VARCHAR(80) NOT NULL,
              payer_or_payee_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
              date DATE NOT NULL,
              note TEXT,
              created_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
              updated_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
              version INTEGER NOT NULL DEFAULT 1,
              deleted_at TIMESTAMPTZ,
              deleted_by UUID REFERENCES users(id) ON DELETE RESTRICT,
              created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
              updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
              CONSTRAINT ck_ledger_entries_amount_positive CHECK (amount_minor > 0),
              CONSTRAINT ck_ledger_entries_currency_cny CHECK (currency = 'CNY'),
              CONSTRAINT ck_ledger_entries_version_positive CHECK (version > 0)
            );
            CREATE INDEX IF NOT EXISTS ix_ledger_entries_workspace_date
              ON ledger_entries (workspace_id, deleted_at, date);

            CREATE TABLE IF NOT EXISTS habits (
              id UUID PRIMARY KEY,
              workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
              owner_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
              title VARCHAR(120) NOT NULL,
              note TEXT,
              frequency habit_frequency NOT NULL,
              start_date DATE NOT NULL,
              status habit_status NOT NULL DEFAULT 'ACTIVE',
              version INTEGER NOT NULL DEFAULT 1,
              deleted_at TIMESTAMPTZ,
              created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
              updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
              CONSTRAINT ck_habits_version_positive CHECK (version > 0)
            );
            CREATE INDEX IF NOT EXISTS ix_habits_workspace_owner
              ON habits (workspace_id, deleted_at, owner_id);

            CREATE TABLE IF NOT EXISTS habit_checkins (
              id UUID PRIMARY KEY,
              workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
              habit_id UUID NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
              actor_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
              frequency_snapshot habit_frequency NOT NULL,
              period_key VARCHAR(10) NOT NULL,
              day DATE NOT NULL,
              occurred_at TIMESTAMPTZ NOT NULL,
              request_id UUID NOT NULL,
              revoked_at TIMESTAMPTZ,
              created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
              CONSTRAINT uq_habit_checkins_period_state UNIQUE (habit_id, frequency_snapshot, period_key, revoked_at)
            );
            CREATE UNIQUE INDEX IF NOT EXISTS uq_habit_checkins_active_period
              ON habit_checkins (habit_id, frequency_snapshot, period_key)
              WHERE revoked_at IS NULL;
            CREATE INDEX IF NOT EXISTS ix_habit_checkins_workspace_period
              ON habit_checkins (workspace_id, period_key);

            CREATE TABLE IF NOT EXISTS anniversaries (
              id UUID PRIMARY KEY,
              workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
              title VARCHAR(160) NOT NULL,
              anchor_date DATE NOT NULL,
              kind anniversary_kind NOT NULL,
              prepare_days INTEGER NOT NULL DEFAULT 0,
              note TEXT,
              created_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
              updated_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
              version INTEGER NOT NULL DEFAULT 1,
              deleted_at TIMESTAMPTZ,
              deleted_by UUID REFERENCES users(id) ON DELETE RESTRICT,
              created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
              updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
              CONSTRAINT ck_anniversaries_prepare_days CHECK (prepare_days IN (0, 1, 3, 7, 14, 30)),
              CONSTRAINT ck_anniversaries_version_positive CHECK (version > 0)
            );
            CREATE INDEX IF NOT EXISTS ix_anniversaries_workspace_anchor
              ON anniversaries (workspace_id, deleted_at, anchor_date);
            """
        )
    )


def downgrade() -> None:
    bind = op.get_bind()
    bind.execute(text("DROP TABLE IF EXISTS anniversaries"))
    bind.execute(text("DROP TABLE IF EXISTS habit_checkins"))
    bind.execute(text("DROP TABLE IF EXISTS habits"))
    bind.execute(text("DROP TABLE IF EXISTS ledger_entries"))
    bind.execute(text("DROP TABLE IF EXISTS domain_commands"))
    bind.execute(text("DROP INDEX IF EXISTS uq_tasks_workspace_source_key"))
    bind.execute(text("ALTER TABLE tasks DROP COLUMN IF EXISTS source_key"))
    bind.execute(text("DROP TYPE IF EXISTS anniversary_kind"))
    bind.execute(text("DROP TYPE IF EXISTS habit_status"))
    bind.execute(text("DROP TYPE IF EXISTS habit_frequency"))
    bind.execute(text("DROP TYPE IF EXISTS ledger_entry_type"))
