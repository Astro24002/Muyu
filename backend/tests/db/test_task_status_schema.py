from __future__ import annotations

from collections.abc import Iterator
from pathlib import Path
from uuid import UUID, uuid4

import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.engine import Engine, make_url
from sqlalchemy.pool import NullPool

from app.db.enums import PUBLIC_TASK_STATUS, TaskStatus
from app.db.models import Task


def _enum_values(engine, type_name: str) -> list[str]:
    with engine.connect() as connection:
        return list(
            connection.scalars(
                text(
                    """
                    SELECT e.enumlabel
                    FROM pg_type t
                    JOIN pg_enum e ON e.enumtypid = t.oid
                    JOIN pg_namespace n ON n.oid = t.typnamespace
                    WHERE n.nspname = current_schema() AND t.typname = :type_name
                    ORDER BY e.enumsortorder
                    """
                ),
                {"type_name": type_name},
            )
        )


def _alembic_config(database_url: str, schema: str) -> Config:
    backend_dir = Path(__file__).resolve().parents[2]
    config = Config(str(backend_dir / "alembic.ini"))
    config.set_main_option("script_location", str(backend_dir / "alembic"))
    config.set_main_option("sqlalchemy.url", database_url.replace("%", "%%"))
    config.attributes["schema"] = schema
    return config


@pytest.fixture
def at_0006(database_url: str) -> Iterator[Engine]:
    schema = f"test_{uuid4().hex}"
    admin_engine = create_engine(database_url, pool_pre_ping=True, poolclass=NullPool)
    with admin_engine.begin() as connection:
        connection.execute(text(f'CREATE SCHEMA "{schema}"'))

    schema_url = make_url(database_url).update_query_dict({"options": f"-csearch_path={schema}"})
    engine = create_engine(schema_url, pool_pre_ping=True, poolclass=NullPool)
    try:
        command.upgrade(_alembic_config(database_url, schema), "0006_trust_sms_devices")
        yield engine
    finally:
        engine.dispose()
        with admin_engine.begin() as connection:
            connection.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        admin_engine.dispose()


def _revert_task_status_to_legacy(engine: Engine) -> None:
    with engine.begin() as connection:
        connection.execute(text("ALTER TABLE tasks DROP CONSTRAINT IF EXISTS fk_tasks_reviewer_user_id"))
        for column_name in (
            "review_rejection_reason",
            "reviewed_at",
            "review_submitted_at",
            "reviewer_user_id",
        ):
            connection.execute(text(f"ALTER TABLE tasks DROP COLUMN IF EXISTS {column_name}"))

        connection.execute(text("ALTER TABLE tasks ALTER COLUMN status DROP DEFAULT"))
        for table_name, column_name in (
            ("tasks", "status"),
            ("task_status_history", "from_status"),
            ("task_status_history", "to_status"),
        ):
            connection.execute(
                text(
                    f"ALTER TABLE {table_name} ALTER COLUMN {column_name} "
                    f"TYPE TEXT USING {column_name}::text"
                )
            )
        connection.execute(
            text("UPDATE tasks SET status = 'IN_PROGRESS' WHERE status IN ('REVIEW', 'BLOCKED')")
        )
        connection.execute(text("UPDATE tasks SET status = 'COMPLETED' WHERE status = 'DONE'"))
        connection.execute(
            text(
                "UPDATE task_status_history SET from_status = 'IN_PROGRESS' "
                "WHERE from_status IN ('REVIEW', 'BLOCKED')"
            )
        )
        connection.execute(
            text(
                "UPDATE task_status_history SET to_status = 'IN_PROGRESS' "
                "WHERE to_status IN ('REVIEW', 'BLOCKED')"
            )
        )
        connection.execute(
            text("UPDATE task_status_history SET from_status = 'COMPLETED' WHERE from_status = 'DONE'")
        )
        connection.execute(
            text("UPDATE task_status_history SET to_status = 'COMPLETED' WHERE to_status = 'DONE'")
        )
        connection.execute(
            text(
                "CREATE TYPE task_status_legacy_test AS ENUM "
                "('TODO', 'IN_PROGRESS', 'WAITING', 'COMPLETED', 'CANCELLED')"
            )
        )
        connection.execute(text("DROP TYPE task_status"))
        connection.execute(text("ALTER TYPE task_status_legacy_test RENAME TO task_status"))
        for table_name, column_name in (
            ("tasks", "status"),
            ("task_status_history", "from_status"),
            ("task_status_history", "to_status"),
        ):
            connection.execute(
                text(
                    f"ALTER TABLE {table_name} ALTER COLUMN {column_name} "
                    f"TYPE task_status USING {column_name}::task_status"
                )
            )
        connection.execute(text("ALTER TABLE tasks ALTER COLUMN status SET DEFAULT 'TODO'"))


def _seed_legacy_status_rows(engine: Engine) -> tuple[UUID, UUID]:
    owner_id = uuid4()
    workspace_id = uuid4()
    waiting_task_id = uuid4()
    completed_task_id = uuid4()
    with engine.begin() as connection:
        connection.execute(
            text("INSERT INTO users (id, phone, status) VALUES (:id, :phone, 'ACTIVE')"),
            {"id": owner_id, "phone": f"+1555{uuid4().int % 10_000_000:07d}"},
        )
        connection.execute(
            text("INSERT INTO workspaces (id, status) VALUES (:id, 'ACTIVE')"),
            {"id": workspace_id},
        )
        task_sql = text(
            """
            INSERT INTO tasks
                (id, workspace_id, task_number, title, status, quadrant, labels, created_by,
                 version, field_versions, lifecycle_version, status_version)
            VALUES
                (:id, :workspace_id, :task_number, :title, CAST(:status AS task_status),
                 'Q1', '[]'::jsonb, :created_by, 1, '{}'::jsonb, 1, 1)
            """
        )
        connection.execute(
            task_sql,
            {
                "id": waiting_task_id,
                "workspace_id": workspace_id,
                "task_number": "26090001",
                "title": "Waiting task",
                "status": "WAITING",
                "created_by": owner_id,
            },
        )
        connection.execute(
            task_sql,
            {
                "id": completed_task_id,
                "workspace_id": workspace_id,
                "task_number": "26090002",
                "title": "Completed task",
                "status": "COMPLETED",
                "created_by": owner_id,
            },
        )
        connection.execute(
            text(
                """
                INSERT INTO task_status_history (id, task_id, from_status, to_status, changed_by)
                VALUES
                    (:waiting_history_id, :waiting_task_id, 'TODO', 'WAITING', :owner_id),
                    (:completed_history_id, :completed_task_id, 'WAITING', 'COMPLETED', :owner_id)
                """
            ),
            {
                "waiting_history_id": uuid4(),
                "completed_history_id": uuid4(),
                "waiting_task_id": waiting_task_id,
                "completed_task_id": completed_task_id,
                "owner_id": owner_id,
            },
        )
    return waiting_task_id, completed_task_id


def test_task_status_enum_and_review_columns(db_engine) -> None:
    inspector = inspect(db_engine)
    expected_statuses = [
        "TODO",
        "IN_PROGRESS",
        "BLOCKED",
        "REVIEW",
        "DONE",
        "CANCELLED",
    ]

    assert _enum_values(db_engine, "task_status") == expected_statuses

    columns = {column["name"]: column for column in inspector.get_columns("tasks")}
    review_columns = {
        "reviewer_user_id",
        "review_submitted_at",
        "reviewed_at",
        "review_rejection_reason",
    }
    assert review_columns <= columns.keys()
    assert all(columns[name]["nullable"] for name in review_columns)

    assert [status.value for status in TaskStatus] == expected_statuses
    assert PUBLIC_TASK_STATUS == {status: status.value for status in TaskStatus}
    assert Task.__table__.c.reviewer_user_id.nullable is True
    assert Task.__table__.c.review_submitted_at.nullable is True
    assert Task.__table__.c.reviewed_at.nullable is True
    assert Task.__table__.c.review_rejection_reason.nullable is True

    foreign_keys = {
        item["name"]: item
        for item in inspector.get_foreign_keys("tasks")
        if "reviewer_user_id" in item["constrained_columns"]
    }
    assert len(foreign_keys) == 1
    reviewer_foreign_key = next(iter(foreign_keys.values()))
    assert reviewer_foreign_key["referred_table"] == "users"
    assert reviewer_foreign_key["referred_columns"] == ["id"]
    assert reviewer_foreign_key["options"]["ondelete"] == "RESTRICT"


def test_upgrade_maps_legacy_task_status_rows_and_history(at_0006: Engine, database_url: str) -> None:
    _revert_task_status_to_legacy(at_0006)
    waiting_task_id, completed_task_id = _seed_legacy_status_rows(at_0006)

    with at_0006.connect() as connection:
        schema = connection.scalar(text("SELECT current_schema()"))
    command.upgrade(_alembic_config(database_url, schema), "head")

    assert _enum_values(at_0006, "task_status") == [
        "TODO",
        "IN_PROGRESS",
        "BLOCKED",
        "REVIEW",
        "DONE",
        "CANCELLED",
    ]

    with at_0006.connect() as connection:
        task_statuses = connection.execute(
            text("SELECT id, status::text FROM tasks ORDER BY task_number")
        ).all()
        history_statuses = connection.execute(
            text(
                "SELECT task_id, from_status::text, to_status::text "
                "FROM task_status_history"
            )
        ).all()
        assert connection.scalar(text("SELECT count(*) FROM tasks")) == 2
        assert connection.scalar(text("SELECT count(*) FROM task_status_history")) == 2

    assert task_statuses == [
        (waiting_task_id, "BLOCKED"),
        (completed_task_id, "DONE"),
    ]
    assert {
        row[0]: (row[1], row[2])
        for row in history_statuses
    } == {
        completed_task_id: ("BLOCKED", "DONE"),
        waiting_task_id: ("TODO", "BLOCKED"),
    }

    # Reuse the seeded completed row to cover REVIEW without changing the
    # two-row history-preservation contract.
    with at_0006.begin() as connection:
        connection.execute(
            text(
                "UPDATE task_status_history SET from_status = 'REVIEW' "
                "WHERE task_id = :task_id"
            ),
            {"task_id": completed_task_id},
        )

    command.downgrade(_alembic_config(database_url, schema), "0006_trust_sms_devices")

    with at_0006.connect() as connection:
        downgraded_tasks = connection.execute(
            text("SELECT id, status::text FROM tasks ORDER BY task_number")
        ).all()
        downgraded_history = connection.execute(
            text(
                "SELECT task_id, from_status::text, to_status::text "
                "FROM task_status_history"
            )
        ).all()
        assert connection.scalar(text("SELECT count(*) FROM task_status_history")) == 2
        downgraded_columns = {
            column["name"] for column in inspect(at_0006).get_columns("tasks")
        }

    assert _enum_values(at_0006, "task_status") == [
        "TODO",
        "IN_PROGRESS",
        "WAITING",
        "COMPLETED",
        "CANCELLED",
    ]
    assert downgraded_tasks == [
        (waiting_task_id, "WAITING"),
        (completed_task_id, "COMPLETED"),
    ]
    assert {
        row[0]: (row[1], row[2])
        for row in downgraded_history
    } == {
        waiting_task_id: ("TODO", "WAITING"),
        completed_task_id: ("IN_PROGRESS", "COMPLETED"),
    }
    assert not {
        "reviewer_user_id",
        "review_submitted_at",
        "reviewed_at",
        "review_rejection_reason",
    } & downgraded_columns
