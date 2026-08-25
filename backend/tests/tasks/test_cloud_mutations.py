from datetime import datetime, timezone
from uuid import uuid4

import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.enums import ConflictStatus, DeviceStatus, MembershipStatus, TaskStatus
from app.db.models import AndroidDevice, TaskConflict, User, WorkspaceMembership
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


def test_task_mutations_are_idempotent_and_record_conflicts(db_engine) -> None:
    with Session(db_engine) as session:
        user, workspace = _workspace(session)
        service = TaskService(session)
        request_id = uuid4()
        task = service.create(workspace.id, user.id, request_id, "Plan", "")
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

        replay = TaskService(session).create(workspace.id, user.id, request_id, "Plan", "")
        assert replay.id == task.id
        assert TaskService(session).last_cursor is None
        assert first_cursor == 1


def test_snapshot_and_changes_are_workspace_scoped(db_engine) -> None:
    with Session(db_engine) as session:
        user, workspace = _workspace(session)
        service = TaskService(session)
        service.create(workspace.id, user.id, uuid4(), "Visible", "")
        session.commit()
        snapshot = SyncService(session).snapshot(workspace.id)
        assert snapshot["cursor"] == 1
        assert snapshot["tasks"][0]["title"] == "Visible"
        changes = SyncService(session).changes(workspace.id, 0)
        assert changes["cursor"] == 1
        assert changes["changes"][0]["resource_type"] == "task"
