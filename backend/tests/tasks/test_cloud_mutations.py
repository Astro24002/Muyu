from datetime import datetime, timezone
from uuid import uuid4

import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.enums import ConflictStatus, DeviceStatus, MembershipStatus, TaskStatus
from app.db.models import AndroidDevice, TaskConflict, User, Workspace, WorkspaceCursor, WorkspaceMembership
from app.tasks.conflicts import TaskConflictError
from app.tasks.service import TaskService
from app.sync.service import SyncService


def _workspace(session: Session) -> tuple[User, object]:
    user = User(phone="+14155552671")
    session.add(user)
    session.flush()
    workspace = __import__("app.db.models", fromlist=["Workspace"]).Workspace(name="Shared")
    session.add(workspace)
    session.flush()
    session.add(
        WorkspaceMembership(
            workspace_id=workspace.id,
            user_id=user.id,
            member_slot=1,
            status=MembershipStatus.ACTIVE,
            joined_at=datetime.now(timezone.utc),
        )
    )
    session.add(__import__("app.db.models", fromlist=["WorkspaceCursor"]).WorkspaceCursor(workspace_id=workspace.id, next_cursor=1))
    session.flush()
    return user, workspace


def _workspace_with_two_users(session: Session) -> tuple[User, User, Workspace]:
    users = [User(phone=f"+1415555{n:04d}") for n in (2671, 2672)]
    session.add_all(users)
    workspace = Workspace(name="Shared")
    session.add(workspace)
    session.flush()
    session.add_all(
        WorkspaceMembership(
            workspace_id=workspace.id,
            user_id=user.id,
            member_slot=index,
            status=MembershipStatus.ACTIVE,
            joined_at=datetime.now(timezone.utc),
        )
        for index, user in enumerate(users, 1)
    )
    session.add(WorkspaceCursor(workspace_id=workspace.id, next_cursor=1))
    session.flush()
    return users[0], users[1], workspace


def test_task_mutations_are_idempotent_and_record_conflicts(db_engine) -> None:
    with Session(db_engine) as session:
        user, workspace = _workspace(session)
        service = TaskService(session)
        request_id = uuid4()
        task = service.create(workspace.id, user.id, request_id, "Plan", "", quadrant="Q1")
        first_cursor = service.last_cursor
        session.commit()

        with pytest.raises(TaskConflictError, match="one or more") as error:
            TaskService(session).patch(
                workspace.id,
                user.id,
                task.id,
                uuid4(),
                {"title": "Changed"},
                {"title": 0},
            )
        assert error.value.code == "field_conflict"
        session.commit()
        conflict = session.scalar(select(TaskConflict).where(TaskConflict.task_id == task.id))
        assert conflict is not None
        assert conflict.status == ConflictStatus.OPEN

        replay = TaskService(session).create(workspace.id, user.id, request_id, "Plan", "", quadrant="Q1")
        assert replay.id == task.id
        assert TaskService(session).last_cursor is None
        assert first_cursor == 1


def test_snapshot_and_changes_are_workspace_scoped(db_engine) -> None:
    with Session(db_engine) as session:
        user, workspace = _workspace(session)
        service = TaskService(session)
        service.create(workspace.id, user.id, uuid4(), "Visible", "", quadrant="Q1")
        session.commit()
        snapshot = SyncService(session).snapshot(workspace.id)
        assert snapshot["cursor"] == 1
        assert snapshot["tasks"][0]["title"] == "Visible"
        assert "assignee_ids" not in snapshot["tasks"][0]
        changes = SyncService(session).changes(workspace.id, 0)
        assert changes["cursor"] == 1
        assert changes["changes"][0]["resource_type"] == "task"
        assert "assignee_ids" not in changes["changes"][0]["resource"]


def test_create_preserves_explicit_fields_and_replay_cursor(db_engine) -> None:
    with Session(db_engine) as session:
        user_a, user_b, workspace = _workspace_with_two_users(session)
        request_id = uuid4()
        service = TaskService(session)
        task = service.create(
            workspace.id,
            user_a.id,
            request_id,
            "  Explicit fields  ",
            description="Details",
            due_at=datetime(2026, 9, 1, 12, tzinfo=timezone.utc),
            planned_start_at=datetime(2026, 8, 28, 9, tzinfo=timezone.utc),
            estimated_minutes=90,
            quadrant="Q1",
        )
        first_cursor = service.last_cursor
        snapshot = service.snapshot(task)
        assert snapshot["title"] == "Explicit fields"
        assert snapshot["description"] == "Details"
        assert snapshot["due_at"] == "2026-09-01T12:00:00+00:00"
        assert snapshot["planned_start_at"] == "2026-08-28T09:00:00+00:00"
        assert snapshot["estimated_minutes"] == 90
        assert snapshot["current_handler_id"] == str(user_a.id)
        assert "assignee_ids" not in snapshot
        assert snapshot["status"] == "TODO"
        replay_service = TaskService(session)
        replay = replay_service.create(
            workspace.id,
            user_a.id,
            request_id,
            "Explicit fields",
            description="Details",
            due_at=datetime(2026, 9, 1, 12, tzinfo=timezone.utc),
            planned_start_at=datetime(2026, 8, 28, 9, tzinfo=timezone.utc),
            estimated_minutes=90,
            quadrant="Q1",
        )
        assert replay.id == task.id
        assert replay_service.last_cursor == first_cursor


def test_patch_allows_independent_fields_and_rejects_stale_field(db_engine) -> None:
    with Session(db_engine) as session:
        user_a, workspace = _workspace(session)
        task = TaskService(session).create(workspace.id, user_a.id, uuid4(), "Initial", quadrant="Q1")
        initial_version = task.version
        first = TaskService(session)
        edited = first.patch(
            workspace.id,
            user_a.id,
            task.id,
            uuid4(),
            {"title": "Renamed", "description": "Updated"},
            {"title": 1, "description": 1},
        )
        assert edited.title == "Renamed"
        assert edited.description == "Updated"
        assert edited.version == initial_version + 1
        second = TaskService(session).patch(
            workspace.id,
            user_a.id,
            task.id,
            uuid4(),
            {"due_at": datetime(2026, 9, 2, tzinfo=timezone.utc)},
            {"due_at": 1},
        )
        assert second.due_at == datetime(2026, 9, 2, tzinfo=timezone.utc)
        with pytest.raises(TaskConflictError) as error:
            TaskService(session).patch(
                workspace.id,
                user_a.id,
                task.id,
                uuid4(),
                {"title": "Stale"},
                {"title": 1},
            )
        assert error.value.code == "field_conflict"
