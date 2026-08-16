from collections.abc import Iterator
import os

import pytest
from sqlalchemy import create_engine, delete, text
from sqlalchemy.engine import Engine

from app.db.migrations import run_migrations
from app.user.models import User, UserSession


@pytest.fixture
def database_url() -> str:
    value = os.environ.get("TEST_DATABASE_URL")
    if not value:
        pytest.fail("TEST_DATABASE_URL is required for database integration tests")
    return value


@pytest.fixture
def db_engine(database_url: str) -> Iterator[Engine]:
    engine = create_engine(database_url, pool_pre_ping=True)
    run_migrations(database_url)
    with engine.begin() as connection:
        if engine.dialect.name == "postgresql":
            connection.execute(text("TRUNCATE TABLE sessions, users RESTART IDENTITY CASCADE"))
        else:
            connection.execute(delete(UserSession))
            connection.execute(delete(User))
    try:
        yield engine
    finally:
        engine.dispose()
