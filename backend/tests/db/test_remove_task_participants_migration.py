from __future__ import annotations

from collections.abc import Iterator
from datetime import datetime, timedelta, timezone
from pathlib import Path
from uuid import uuid4

import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.engine import Engine, make_url
from sqlalchemy.orm import Session
from sqlalchemy.pool import NullPool

from app.db.enums import ConflictStatus, MembershipStatus, TaskApprovalRequestStatus, TaskQuadrant, TaskStatus
from app.db.models import (
    ActivityEvent,
    DelayRecord,
    Task,
    TaskComment,
    TaskConflict,
    TaskHandlerHistory,
    TaskStatusHistory,
    User,
    Workspace,
    WorkspaceMembership,
)


_NEW_APPROVAL_REQUEST_TYPES = [
    "TASK_UPDATE",
    "QUADRANT_UPDATE",
    "STATUS_UPDATE",
    "TASK_DELETE",
    "TASK_RESTORE",
    "COMMENT_DELETE",
    "HANDLER_TRANSFER",
    "CLASSIFICATION_CREATE",
]
_OLD_APPROVAL_REQUEST_TYPES = [*_NEW_APPROVAL_REQUEST_TYPES[:6], "ASSIGNEE_UPDATE", "HANDLER_TRANSFER"]


def _config(database_url: str, schema: str) -> Config:
    backend_dir = Path(__file__).resolve().parents[2]
    config = Config(str(backend_dir / "alembic.ini"))
    config.set_main_option("script_location", str(backend_dir / "alembic"))
    config.set_main_option("sqlalchemy.url", database_url.replace("%", "%%"))
    config.attributes["schema"] = schema
    return config


@pytest.fixture
def at_0004(database_url: str) -> Iterator[Engine]:
    schema = f"test_{uuid4().hex}"
    admin_engine = create_engine(database_url, pool_pre_ping=True, poolclass=NullPool)
    with admin_engine.begin() as connection:
        connection.execute(text(f'CREATE SCHEMA "{schema}"'))

    schema_url = make_url(database_url).update_query_dict({"options": f"-csearch_path={schema}"})
    engine = create_engine(schema_url, pool_pre_ping=True, poolclass=NullPool)
    try:
        command.upgrade(_config(database_url, schema), "0004_task_labels_quadrant")
        yield engine
    finally:
        engine.dispose()
        with admin_engine.begin() as connection:
            connection.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        admin_engine.dispose()


def _seed_legacy_schema(engine: Engine) -> dict[str, object]:
    with engine.begin() as connection:
        connection.execute(
            text(
                "ALTER TYPE task_approval_request_type "
                "ADD VALUE IF NOT EXISTS 'ASSIGNEE_UPDATE' BEFORE 'HANDLER_TRANSFER'"
            )
        )
        connection.execute(
            text(
                """
                CREATE TABLE task_assignees (
                    task_id UUID NOT NULL REFERENCES tasks (id) ON DELETE CASCADE,
                    user_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
                    PRIMARY KEY (task_id, user_id)
                )
                """
            )
        )

    now = datetime.now(timezone.utc)
    with Session(engine, expire_on_commit=False) as session:
        owner = User(phone=f"+1555{uuid4().int % 10_000_000:07d}")
        partner = User(phone=f"+1555{uuid4().int % 10_000_000:07d}")
        workspace = Workspace()
        session.add_all([owner, partner, workspace])
        session.flush()
        session.add_all(
            [
                WorkspaceMembership(
                    workspace_id=workspace.id,
                    user_id=owner.id,
                    member_slot=1,
                    status=MembershipStatus.ACTIVE,
                ),
                WorkspaceMembership(
                    workspace_id=workspace.id,
                    user_id=partner.id,
                    member_slot=2,
                    status=MembershipStatus.ACTIVE,
                ),
            ]
        )
        task = Task(
            workspace_id=workspace.id,
            task_number=f"2609{uuid4().int % 10000:04d}",
            title="Migration task",
            quadrant=TaskQuadrant.Q1,
            labels=["工作", "婚礼"],
            current_handler_id=owner.id,
            created_by=owner.id,
            field_versions={"title": 1, "assignee_ids": 7},
        )
        session.add(task)
        session.flush()
        session.execute(
            text(
                "INSERT INTO task_assignees (task_id, user_id) VALUES (:task_id, :user_id)"
            ),
            {"task_id": task.id, "user_id": partner.id},
        )

        status_history = TaskStatusHistory(
            task_id=task.id,
            from_status=TaskStatus.TODO,
            to_status=TaskStatus.IN_PROGRESS,
            changed_by=owner.id,
        )
        handler_history = TaskHandlerHistory(
            task_id=task.id,
            from_user_id=None,
            to_user_id=owner.id,
            changed_by=owner.id,
        )
        comment = TaskComment(
            workspace_id=workspace.id,
            task_id=task.id,
            author_user_id=owner.id,
            body="Keep this audit row",
        )
        delay = DelayRecord(
            workspace_id=workspace.id,
            task_id=task.id,
            actor_user_id=owner.id,
            original_due_at=now,
            new_due_at=now + timedelta(minutes=30),
            delayed_at=now,
            delay_duration_minutes=30,
            reason="OTHER",
        )
        event = ActivityEvent(
            workspace_id=workspace.id,
            task_id=task.id,
            actor_user_id=owner.id,
            event_type="MIGRATION_TEST",
            payload={"preserve": True},
        )
        assignee_conflict = TaskConflict(
            workspace_id=workspace.id,
            task_id=task.id,
            target="assignee_ids",
            base_value=[str(owner.id)],
            current_value=[str(owner.id)],
            proposed_value=[str(partner.id)],
            base_version=1,
            current_version=2,
            request_id=uuid4(),
            status=ConflictStatus.OPEN,
        )
        title_conflict = TaskConflict(
            workspace_id=workspace.id,
            task_id=task.id,
            target="title",
            base_value="Before",
            current_value="Current",
            proposed_value="Proposed",
            base_version=1,
            current_version=2,
            request_id=uuid4(),
            status=ConflictStatus.OPEN,
        )
        session.add_all([
            status_history,
            handler_history,
            comment,
            delay,
            event,
            assignee_conflict,
            title_conflict,
        ])
        session.flush()

        preserved_request_id = uuid4()
        deleted_request_id = uuid4()
        approval_sql = text(
            """
            INSERT INTO task_approval_requests
                (id, workspace_id, task_id, requester_id, approver_id, request_type,
                 proposed_changes, base_field_versions, request_id, status)
            VALUES
                (:id, :workspace_id, :task_id, :requester_id, :approver_id,
                 CAST(:request_type AS task_approval_request_type),
                 CAST(:proposed_changes AS jsonb), CAST(:base_field_versions AS jsonb),
                 :request_id, CAST(:status AS task_approval_request_status))
            """
        )
        for request_id, request_type in (
            (preserved_request_id, "TASK_UPDATE"),
            (deleted_request_id, "ASSIGNEE_UPDATE"),
        ):
            session.execute(
                approval_sql,
                {
                    "id": uuid4(),
                    "workspace_id": workspace.id,
                    "task_id": task.id,
                    "requester_id": partner.id,
                    "approver_id": owner.id,
                    "request_type": request_type,
                    "proposed_changes": "{}",
                    "base_field_versions": "{}",
                    "request_id": request_id,
                    "status": TaskApprovalRequestStatus.PENDING.value,
                },
            )
        session.commit()

    return {
        "workspace_id": workspace.id,
        "task_id": task.id,
        "owner_id": owner.id,
        "preserved_request_id": preserved_request_id,
        "deleted_request_id": deleted_request_id,
        "status_history_id": status_history.id,
        "handler_history_id": handler_history.id,
        "comment_id": comment.id,
        "delay_id": delay.id,
        "event_id": event.id,
        "assignee_conflict_id": assignee_conflict.id,
        "title_conflict_id": title_conflict.id,
    }


def _enum_labels(engine: Engine, type_name: str) -> list[str]:
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


def _upgrade_to_head(engine: Engine, database_url: str) -> None:
    with engine.connect() as connection:
        schema = connection.scalar(text("SELECT current_schema()"))
    command.upgrade(_config(database_url, schema), "head")


def _downgrade_to_0004(engine: Engine, database_url: str) -> None:
    with engine.connect() as connection:
        schema = connection.scalar(text("SELECT current_schema()"))
    command.downgrade(_config(database_url, schema), "0004_task_labels_quadrant")


def test_upgrade_adds_enum_value_when_public_has_same_named_enum(
    at_0004: Engine, database_url: str
) -> None:
    admin_engine = create_engine(database_url, pool_pre_ping=True, poolclass=NullPool)
    backup_name = f"task_approval_request_type_backup_{uuid4().hex}"
    renamed_existing_type = False
    created_public_type = False
    try:
        with admin_engine.begin() as connection:
            existing_type = connection.scalar(
                text(
                    "SELECT t.typtype "
                    "FROM pg_type t "
                    "JOIN pg_namespace n ON n.oid = t.typnamespace "
                    "WHERE n.nspname = 'public' "
                    "AND t.typname = 'task_approval_request_type'"
                )
            )
            if existing_type is not None:
                assert existing_type == "e"
                connection.execute(
                    text(
                        "ALTER TYPE public.task_approval_request_type "
                        f"RENAME TO {backup_name}"
                    )
                )
            connection.execute(
                text(
                    "CREATE TYPE public.task_approval_request_type "
                    "AS ENUM ('CLASSIFICATION_CREATE')"
                )
            )
        renamed_existing_type = existing_type is not None
        created_public_type = True

        _upgrade_to_head(at_0004, database_url)

        assert _enum_labels(at_0004, "task_approval_request_type") == _NEW_APPROVAL_REQUEST_TYPES
    finally:
        with admin_engine.begin() as connection:
            if created_public_type:
                connection.execute(text("DROP TYPE public.task_approval_request_type"))
            if renamed_existing_type:
                connection.execute(
                    text(
                        "ALTER TYPE public."
                        f"{backup_name} RENAME TO task_approval_request_type"
                    )
                )
        admin_engine.dispose()


def test_upgrade_from_0004_preserves_owner_history_and_non_assignee_approvals(
    at_0004: Engine, database_url: str
) -> None:
    data = _seed_legacy_schema(at_0004)

    _upgrade_to_head(at_0004, database_url)

    assert "task_assignees" not in inspect(at_0004).get_table_names()
    assert _enum_labels(at_0004, "task_approval_request_type") == _NEW_APPROVAL_REQUEST_TYPES
    with at_0004.connect() as connection:
        assert connection.scalar(
            text("SELECT current_handler_id FROM tasks WHERE id = :task_id"),
            {"task_id": data["task_id"]},
        ) == data["owner_id"]
        assert connection.scalar(
            text("SELECT labels FROM tasks WHERE id = :task_id"),
            {"task_id": data["task_id"]},
        ) == ["工作"]
        assert connection.scalar(
            text(
                "SELECT count(*) FROM task_approval_requests "
                "WHERE request_id = :request_id"
            ),
            {"request_id": data["preserved_request_id"]},
        ) == 1
        assert connection.scalar(
            text(
                "SELECT count(*) FROM task_approval_requests "
                "WHERE request_id = :request_id"
            ),
            {"request_id": data["deleted_request_id"]},
        ) == 0
        assert connection.scalar(
            text("SELECT field_versions FROM tasks WHERE id = :task_id"),
            {"task_id": data["task_id"]},
        ) == {"title": 1}
        assert connection.scalar(
            text("SELECT count(*) FROM task_conflicts WHERE id = :conflict_id"),
            {"conflict_id": data["assignee_conflict_id"]},
        ) == 0
        assert connection.scalar(
            text("SELECT count(*) FROM task_conflicts WHERE id = :conflict_id"),
            {"conflict_id": data["title_conflict_id"]},
        ) == 1
        for table, key in (
            ("task_status_history", "status_history_id"),
            ("task_handler_history", "handler_history_id"),
            ("task_comments", "comment_id"),
            ("delay_records", "delay_id"),
            ("activity_events", "event_id"),
        ):
            assert connection.scalar(
                text(f"SELECT count(*) FROM {table} WHERE id = :row_id"),
                {"row_id": data[key]},
            ) == 1


def test_upgrade_rejects_null_owner_before_destructive_steps(
    at_0004: Engine, database_url: str
) -> None:
    data = _seed_legacy_schema(at_0004)
    with at_0004.begin() as connection:
        connection.execute(
            text("UPDATE tasks SET current_handler_id = NULL WHERE id = :task_id"),
            {"task_id": data["task_id"]},
        )

    with pytest.raises(RuntimeError, match="current_handler_id.*ACTIVE"):
        _upgrade_to_head(at_0004, database_url)

    assert "task_assignees" in inspect(at_0004).get_table_names()
    # PostgreSQL may retain the 0009 enum value even though the earlier
    # destructive migration is aborted and its schema changes are rolled back.
    assert _enum_labels(at_0004, "task_approval_request_type") == [
        *_OLD_APPROVAL_REQUEST_TYPES,
        "CLASSIFICATION_CREATE",
    ]
    with at_0004.connect() as connection:
        assert connection.scalar(
            text(
                "SELECT count(*) FROM task_approval_requests "
                "WHERE request_id = :request_id"
            ),
            {"request_id": data["deleted_request_id"]},
        ) == 1


def test_upgrade_rejects_non_active_owner(at_0004: Engine, database_url: str) -> None:
    data = _seed_legacy_schema(at_0004)
    with at_0004.begin() as connection:
        connection.execute(
            text(
                "UPDATE workspace_memberships SET status = :status "
                "WHERE workspace_id = :workspace_id AND user_id = :user_id"
            ),
            {
                "status": MembershipStatus.REVOKED.value,
                "workspace_id": data["workspace_id"],
                "user_id": data["owner_id"],
            },
        )

    with pytest.raises(RuntimeError, match="current_handler_id.*ACTIVE"):
        _upgrade_to_head(at_0004, database_url)


def test_downgrade_restores_schema_shape_without_participant_rows(
    at_0004: Engine, database_url: str
) -> None:
    data = _seed_legacy_schema(at_0004)
    _upgrade_to_head(at_0004, database_url)
    _downgrade_to_0004(at_0004, database_url)

    # The downgrade is migration-tooling support only: it recreates the old
    # table and enum label, but it cannot restore the participant rows removed
    # by the upgrade.
    assert "task_assignees" in inspect(at_0004).get_table_names()
    assert _enum_labels(at_0004, "task_approval_request_type") == _OLD_APPROVAL_REQUEST_TYPES
    with at_0004.connect() as connection:
        assert connection.scalar(text("SELECT count(*) FROM task_assignees")) == 0
        assert connection.scalar(
            text(
                "SELECT count(*) FROM task_approval_requests "
                "WHERE request_id = :request_id"
            ),
            {"request_id": data["preserved_request_id"]},
        ) == 1
