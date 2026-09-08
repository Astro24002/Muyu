from __future__ import annotations

from collections.abc import Iterator
from pathlib import Path
from uuid import UUID, uuid4

import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, select, text
from sqlalchemy.engine import Engine, make_url
from sqlalchemy.orm import Session
from sqlalchemy.pool import NullPool

from app.db.enums import MembershipStatus, TaskQuadrant
from app.db.models import Task, User, Workspace, WorkspaceClassification, WorkspaceMembership


def _config(database_url: str, schema: str) -> Config:
    backend_dir = Path(__file__).resolve().parents[2]
    config = Config(str(backend_dir / "alembic.ini"))
    config.set_main_option("script_location", str(backend_dir / "alembic"))
    config.set_main_option("sqlalchemy.url", database_url.replace("%", "%%"))
    config.attributes["schema"] = schema
    return config


@pytest.fixture
def at_0011(database_url: str) -> Iterator[Engine]:
    schema = f"test_{uuid4().hex}"
    admin_engine = create_engine(database_url, pool_pre_ping=True, poolclass=NullPool)
    with admin_engine.begin() as connection:
        connection.execute(text(f'CREATE SCHEMA "{schema}"'))

    schema_url = make_url(database_url).update_query_dict(
        {"options": f"-csearch_path={schema}"}
    )
    engine = create_engine(schema_url, pool_pre_ping=True, poolclass=NullPool)
    try:
        command.upgrade(_config(database_url, schema), "0011_legacy_label_backfill")
        yield engine
    finally:
        engine.dispose()
        with admin_engine.begin() as connection:
            connection.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        admin_engine.dispose()


def _user(phone_suffix: str) -> User:
    return User(phone=f"+1555{phone_suffix}")


def test_default_classification_cleanup_removes_system_rows_and_preserves_history(
    at_0011: Engine,
    database_url: str,
) -> None:
    with Session(at_0011) as session:
        first = _user("1000001")
        second = _user("1000002")
        pending_only = _user("1000003")
        existing_creator = _user("1000004")
        seeded = Workspace()
        skipped = Workspace()
        existing = Workspace()
        session.add_all([first, second, pending_only, existing_creator, seeded, skipped, existing])
        session.flush()
        session.add_all(
            [
                # Slot 1 is selected even when its row was created after slot 2.
                WorkspaceMembership(
                    workspace_id=seeded.id,
                    user_id=second.id,
                    member_slot=2,
                    status=MembershipStatus.ACTIVE,
                ),
                WorkspaceMembership(
                    workspace_id=seeded.id,
                    user_id=first.id,
                    member_slot=1,
                    status=MembershipStatus.ACTIVE,
                ),
                WorkspaceMembership(
                    workspace_id=skipped.id,
                    user_id=pending_only.id,
                    member_slot=1,
                    status=MembershipStatus.PENDING,
                ),
                WorkspaceMembership(
                    workspace_id=existing.id,
                    user_id=existing_creator.id,
                    member_slot=1,
                    status=MembershipStatus.ACTIVE,
                ),
            ]
        )
        legacy_default_task = Task(
            workspace_id=seeded.id,
            task_number="26090001",
            title="历史默认分类任务",
            quadrant=TaskQuadrant.Q1,
            labels=["默认"],
            current_handler_id=first.id,
            created_by=first.id,
        )
        legacy_unclassified_task = Task(
            workspace_id=seeded.id,
            task_number="26090002",
            title="历史未分类任务",
            quadrant=TaskQuadrant.Q1,
            labels=[],
            current_handler_id=first.id,
            created_by=first.id,
        )
        legacy_spaced_default_task = Task(
            workspace_id=seeded.id,
            task_number="26090003",
            title="历史带空格默认分类任务",
            quadrant=TaskQuadrant.Q1,
            labels=[" 默认 "],
            current_handler_id=first.id,
            created_by=first.id,
        )
        preserved_classification = WorkspaceClassification(
            workspace_id=seeded.id,
            name="工作",
            normalized_name="工作",
            created_by=first.id,
        )
        preserved_classification_task = Task(
            workspace_id=seeded.id,
            task_number="26090004",
            title="保留的已分类任务",
            quadrant=TaskQuadrant.Q1,
            labels=["工作"],
            current_handler_id=first.id,
            created_by=first.id,
        )
        session.add_all(
            [
                legacy_default_task,
                legacy_unclassified_task,
                legacy_spaced_default_task,
                preserved_classification,
                preserved_classification_task,
            ]
        )
        preserved = WorkspaceClassification(
            workspace_id=existing.id,
            name="默认",
            normalized_name="默认",
            created_by=existing_creator.id,
        )
        session.add(preserved)
        session.flush()
        seeded_id = seeded.id
        skipped_id = skipped.id
        existing_id = existing.id
        first_id = first.id
        session.commit()

    schema = at_0011.connect().scalar(text("SELECT current_schema()"))
    config = _config(database_url, schema)
    command.upgrade(config, "0012_default_classification")

    with Session(at_0011) as session:
        seeded_default = session.scalar(
            select(WorkspaceClassification).where(
                WorkspaceClassification.workspace_id == seeded_id,
                WorkspaceClassification.normalized_name == "默认",
            )
        )
        assert seeded_default is not None
        assert seeded_default.created_by == first_id

    command.upgrade(config, "head")
    # A second execution of both revisions must remain idempotent.
    command.downgrade(config, "0011_legacy_label_backfill")
    command.upgrade(config, "head")

    with Session(at_0011) as session:
        assert session.scalars(
            select(WorkspaceClassification).where(
                WorkspaceClassification.workspace_id == skipped_id,
            )
        ).all() == []

        existing_rows = session.scalars(
            select(WorkspaceClassification).where(
                WorkspaceClassification.workspace_id == existing_id,
                WorkspaceClassification.normalized_name == "默认",
            )
        ).all()
        assert existing_rows == []

        seeded_tasks = session.scalars(
            select(Task).where(Task.workspace_id == seeded_id).order_by(Task.task_number)
        ).all()
        assert [task.labels for task in seeded_tasks] == [[], [], [], ["工作"]]
        assert [
            classification.name
            for classification in session.scalars(
                select(WorkspaceClassification)
                .where(WorkspaceClassification.workspace_id == seeded_id)
                .order_by(WorkspaceClassification.normalized_name)
            )
        ] == ["工作"]
