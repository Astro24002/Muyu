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
