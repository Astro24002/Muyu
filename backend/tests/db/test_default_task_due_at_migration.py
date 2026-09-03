from __future__ import annotations

from collections.abc import Iterator
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine, make_url
from sqlalchemy.orm import Session
from sqlalchemy.pool import NullPool

from app.db.enums import MembershipStatus
from app.db.models import Task, User, Workspace, WorkspaceMembership


def _config(database_url: str, schema: str) -> Config:
    backend_dir = Path(__file__).resolve().parents[2]
    config = Config(str(backend_dir / "alembic.ini"))
    config.set_main_option("script_location", str(backend_dir / "alembic"))
    config.set_main_option("sqlalchemy.url", database_url.replace("%", "%%"))
    config.attributes["schema"] = schema
    return config


@pytest.fixture
def at_0007(database_url: str) -> Iterator[Engine]:
    schema = f"test_{uuid4().hex}"
    admin_engine = create_engine(database_url, pool_pre_ping=True, poolclass=NullPool)
    with admin_engine.begin() as connection:
        connection.execute(text(f'CREATE SCHEMA "{schema}"'))

    schema_url = make_url(database_url).update_query_dict(
        {"options": f"-csearch_path={schema}"}
    )
    engine = create_engine(schema_url, pool_pre_ping=True, poolclass=NullPool)
    try:
        command.upgrade(_config(database_url, schema), "0007_six_state_task_status")
        yield engine
    finally:
        engine.dispose()
        with admin_engine.begin() as connection:
            connection.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        admin_engine.dispose()


def test_upgrade_backfills_only_missing_task_deadlines(
    at_0007: Engine, database_url: str
) -> None:
    created_at = datetime(2026, 9, 3, 10, 30, tzinfo=timezone.utc)
    explicit_due_at = datetime(2026, 9, 10, 18, tzinfo=timezone.utc)
    with Session(at_0007) as session:
        user = User(phone=f"+1555{uuid4().int % 10_000_000:07d}")
        workspace = Workspace(name="Deadline migration")
        session.add_all([user, workspace])
        session.flush()
        session.add(
            WorkspaceMembership(
                workspace_id=workspace.id,
                user_id=user.id,
                member_slot=1,
                status=MembershipStatus.ACTIVE,
            )
        )
        missing = Task(
            workspace_id=workspace.id,
            task_number="26090001",
            title="Missing deadline",
            quadrant="Q1",
            labels=[],
            current_handler_id=user.id,
            created_by=user.id,
        )
        explicit = Task(
            workspace_id=workspace.id,
            task_number="26090002",
            title="Explicit deadline",
            quadrant="Q2",
            labels=[],
            current_handler_id=user.id,
            created_by=user.id,
            due_at=explicit_due_at,
        )
        session.add_all([missing, explicit])
        session.flush()
        missing.created_at = created_at
        explicit.created_at = created_at
        session.commit()
        missing_id = missing.id
        explicit_id = explicit.id

    with at_0007.connect() as connection:
        schema = connection.scalar(text("SELECT current_schema()"))
    command.upgrade(_config(database_url, schema), "head")

    with Session(at_0007) as session:
        assert session.get(Task, missing_id).due_at == datetime(
            2026, 9, 17, 10, 30, tzinfo=timezone.utc
        )
        assert session.get(Task, explicit_id).due_at == explicit_due_at
