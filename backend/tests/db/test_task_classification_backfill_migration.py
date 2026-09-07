from __future__ import annotations

from collections.abc import Iterator
from datetime import datetime, timezone
from pathlib import Path
from uuid import UUID, uuid4

import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine, make_url
from sqlalchemy.orm import Session
from sqlalchemy.pool import NullPool

from app.db.enums import TaskQuadrant
from app.db.models import Task, User, Workspace, WorkspaceClassification


def _config(database_url: str, schema: str) -> Config:
    backend_dir = Path(__file__).resolve().parents[2]
    config = Config(str(backend_dir / "alembic.ini"))
    config.set_main_option("script_location", str(backend_dir / "alembic"))
    config.set_main_option("sqlalchemy.url", database_url.replace("%", "%%"))
    config.attributes["schema"] = schema
    return config


@pytest.fixture
def at_0010(database_url: str) -> Iterator[Engine]:
    schema = f"test_{uuid4().hex}"
    admin_engine = create_engine(database_url, pool_pre_ping=True, poolclass=NullPool)
    with admin_engine.begin() as connection:
        connection.execute(text(f'CREATE SCHEMA "{schema}"'))

    schema_url = make_url(database_url).update_query_dict(
        {"options": f"-csearch_path={schema}"}
    )
    engine = create_engine(schema_url, pool_pre_ping=True, poolclass=NullPool)
    try:
        command.upgrade(_config(database_url, schema), "0010_single_task_classification")
        yield engine
    finally:
        engine.dispose()
        with admin_engine.begin() as connection:
            connection.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        admin_engine.dispose()


def _task(
    workspace_id: UUID,
    created_by: UUID,
    number: str,
    label: object,
    created_at: datetime,
) -> Task:
    return Task(
        workspace_id=workspace_id,
        task_number=number,
        title=number,
        quadrant=TaskQuadrant.Q1,
        labels=[label],
        current_handler_id=created_by,
        created_by=created_by,
        created_at=created_at,
    )


def test_backfill_creates_deterministic_approved_classifications(at_0010, database_url: str) -> None:
    first_created_at = datetime(2026, 1, 1, tzinfo=timezone.utc)
    second_created_at = datetime(2026, 1, 2, tzinfo=timezone.utc)
    with Session(at_0010) as session:
        first_user = User(phone=f"+1555{uuid4().int % 10_000_000:07d}")
        second_user = User(phone=f"+1555{uuid4().int % 10_000_000:07d}")
        other_workspace_user = User(phone=f"+1555{uuid4().int % 10_000_000:07d}")
        workspace = Workspace()
        other_workspace = Workspace()
        session.add_all([first_user, second_user, other_workspace_user, workspace, other_workspace])
        session.flush()

        existing = WorkspaceClassification(
            workspace_id=workspace.id,
            name="已有",
            normalized_name="已有",
            created_by=second_user.id,
        )
        session.add(existing)
        session.add_all(
            [
                # The earliest task determines both display spelling and creator.
                _task(workspace.id, first_user.id, "26090001", " Work ", first_created_at),
                _task(workspace.id, second_user.id, "26090002", "work", second_created_at),
                # Existing approved rows are preserved rather than duplicated.
                _task(workspace.id, first_user.id, "26090003", " 已有 ", first_created_at),
                # Invalid legacy values remain untouched and do not become rows.
                _task(workspace.id, first_user.id, "26090004", "   ", second_created_at),
                _task(workspace.id, first_user.id, "26090005", "ßßß", second_created_at),
                _task(workspace.id, first_user.id, "26090006", 123, second_created_at),
                _task(workspace.id, first_user.id, "26090007", "toolong", second_created_at),
                Task(
                    workspace_id=workspace.id,
                    task_number="26090008",
                    title="empty",
                    quadrant=TaskQuadrant.Q1,
                    labels=[],
                    current_handler_id=first_user.id,
                    created_by=first_user.id,
                ),
                # The same normalized key is independent per workspace.
                _task(other_workspace.id, other_workspace_user.id, "26090009", "WORK", first_created_at),
            ]
        )
        session.flush()
        workspace_id = workspace.id
        other_workspace_id = other_workspace.id
        first_user_id = first_user.id
        second_user_id = second_user.id
        existing_id = existing.id
        session.commit()

    with at_0010.connect() as connection:
        schema = connection.scalar(text("SELECT current_schema()"))
    command.upgrade(_config(database_url, schema), "head")

    with Session(at_0010) as session:
        rows = session.execute(
            text(
                """
                SELECT id, workspace_id, name, normalized_name, created_by, created_at
                  FROM workspace_classifications
                 ORDER BY workspace_id, normalized_name
                """
            )
        ).mappings().all()

        assert len(rows) == 3
        workspace_rows = [row for row in rows if row["workspace_id"] == workspace_id]
        assert {(row["name"], row["normalized_name"]) for row in workspace_rows} == {
            ("Work", "work"),
            ("已有", "已有"),
        }
        work = next(row for row in workspace_rows if row["normalized_name"] == "work")
        assert work["created_by"] == first_user_id
        assert work["created_at"] == first_created_at
        preserved = next(row for row in workspace_rows if row["normalized_name"] == "已有")
        assert preserved["id"] == existing_id
        assert preserved["created_by"] == second_user_id
        assert len([row for row in rows if row["workspace_id"] == other_workspace_id]) == 1
