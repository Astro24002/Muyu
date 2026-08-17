from sqlalchemy import inspect

from app.db.migrations import run_migrations


def test_migrations_create_users_and_sessions(database_url: str) -> None:
    run_migrations(database_url)
    from sqlalchemy import create_engine

    engine = create_engine(database_url)
    inspector = inspect(engine)

    assert {"users", "sessions"}.issubset(inspector.get_table_names())
    assert {column["name"] for column in inspector.get_columns("users")} >= {
        "id",
        "phone",
        "password_hash",
        "nickname",
        "avatar_key",
        "role",
        "created_at",
        "updated_at",
    }
    assert {column["name"] for column in inspector.get_columns("sessions")} >= {
        "id",
        "user_id",
        "refresh_token_hash",
        "expires_at",
        "revoked_at",
        "created_at",
    }
    engine.dispose()


def test_migrations_create_task_core_tables(database_url: str) -> None:
    run_migrations(database_url)
    from sqlalchemy import create_engine

    engine = create_engine(database_url)
    inspector = inspect(engine)

    assert {
        "tasks",
        "task_assignees",
        "task_user_positions",
        "task_status_history",
        "task_handler_history",
        "activity_events",
    }.issubset(inspector.get_table_names())
    assert {column["name"] for column in inspector.get_columns("tasks")} >= {
        "id",
        "parent_task_id",
        "title",
        "description",
        "status",
        "current_handler_id",
        "planned_start_at",
        "due_at",
        "estimated_minutes",
        "completed_at",
        "created_by",
        "version",
        "status_version",
        "deleted_at",
        "created_at",
        "updated_at",
    }
    assert {column["name"] for column in inspector.get_columns("activity_events")} >= {
        "id",
        "actor_user_id",
        "target_type",
        "target_id",
        "action",
        "before_json",
        "after_json",
        "payload_json",
        "aggregate_version",
        "request_id",
        "created_at",
    }
    engine.dispose()


def test_migrations_create_delay_records(database_url: str) -> None:
    run_migrations(database_url)
    from sqlalchemy import create_engine

    engine = create_engine(database_url)
    inspector = inspect(engine)

    assert "delay_records" in inspector.get_table_names()
    assert {column["name"] for column in inspector.get_columns("delay_records")} == {
        "id",
        "task_id",
        "user_id",
        "original_due_at",
        "new_due_at",
        "delayed_at",
        "delay_duration_minutes",
        "reason",
        "note",
        "created_at",
    }
    assert {index["name"] for index in inspector.get_indexes("delay_records")} >= {
        "ix_delay_records_task_id"
    }
    assert {
        tuple(foreign_key["constrained_columns"])
        for foreign_key in inspector.get_foreign_keys("delay_records")
    } >= {("task_id",), ("user_id",)}
    engine.dispose()
