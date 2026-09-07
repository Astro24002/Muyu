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

from app.db.enums import MembershipStatus
from app.db.models import User, Workspace, WorkspaceClassification, WorkspaceMembership


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


def test_default_classification_migration_seeds_active_workspaces_idempotently(
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
        preserved_id = preserved.id
        session.commit()

    schema = at_0011.connect().scalar(text("SELECT current_schema()"))
    config = _config(database_url, schema)
    command.upgrade(config, "head")
    # A second execution of the revision must not create a duplicate row.
    command.downgrade(config, "0011_legacy_label_backfill")
    command.upgrade(config, "head")

    with Session(at_0011) as session:
        seeded_default = session.scalar(
            select(WorkspaceClassification).where(
                WorkspaceClassification.workspace_id == seeded_id,
                WorkspaceClassification.normalized_name == "默认",
            )
        )
        assert seeded_default is not None
        assert seeded_default.created_by == first_id

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
        assert len(existing_rows) == 1
        assert existing_rows[0].id == preserved_id
