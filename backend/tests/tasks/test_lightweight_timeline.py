from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.enums import MembershipStatus
from app.db.models import DelayRecord, Task, User, Workspace, WorkspaceCursor, WorkspaceMembership
from app.tasks.comments import add_comment
from app.tasks.delays import add_delay, list_delays
from app.tasks.conflicts import TaskConflictError
from app.tasks.service import TaskService


def _workspace(session):
    user = User(phone=f"+1415555{uuid4().int % 10000:04d}")
    workspace = Workspace(name="Timeline")
    session.add_all([user, workspace])
    session.flush()
    session.add(WorkspaceMembership(workspace_id=workspace.id, user_id=user.id, member_slot=1, status=MembershipStatus.ACTIVE, joined_at=datetime.now(timezone.utc)))
    session.add(WorkspaceCursor(workspace_id=workspace.id, next_cursor=1))
    session.flush()
    return user, workspace


def test_three_delays_are_append_only_and_match_snapshot(db_engine):
    with Session(db_engine) as session:
        user, workspace = _workspace(session)
        task = TaskService(session).create(workspace.id, user.id, uuid4(), "追踪", due_at=datetime(2026, 8, 27, tzinfo=timezone.utc))
        for minute in (60, 120, 180):
            add_delay(session, workspace.id, user.id, task.id, task.due_at + timedelta(minutes=minute), "NO_TIME", request_id=uuid4())
            session.commit()
        refreshed = session.get(Task, task.id)
        snapshot = TaskService(session).snapshot(refreshed)
        assert snapshot["delay_count"] == 3
        assert snapshot["total_delay_minutes"] == 360
        assert len(list_delays(session, workspace.id, task.id)) == 3


def test_delay_requires_minute_and_other_note_and_replay_is_immutable(db_engine):
    with Session(db_engine) as session:
        user, workspace = _workspace(session)
        due = datetime(2026, 8, 27, tzinfo=timezone.utc)
        task = TaskService(session).create(workspace.id, user.id, uuid4(), "追踪", due_at=due)
        with pytest.raises(TaskConflictError) as early:
            add_delay(session, workspace.id, user.id, task.id, due + timedelta(seconds=30), "NO_TIME", request_id=uuid4())
        assert early.value.code == "invalid_request"
        with pytest.raises(TaskConflictError) as missing_note:
            add_delay(session, workspace.id, user.id, task.id, due + timedelta(minutes=2), "OTHER", request_id=uuid4())
        assert missing_note.value.code == "invalid_request"
        request_id = uuid4()
        first = add_delay(session, workspace.id, user.id, task.id, due + timedelta(minutes=10), "OTHER", "because", request_id)
        session.commit()
        cursor = TaskService(session).last_cursor
        replay = add_delay(session, workspace.id, user.id, task.id, due + timedelta(minutes=10), "OTHER", "because", request_id)
        assert replay.id == first.id
        assert len(session.scalars(select(DelayRecord).where(DelayRecord.task_id == task.id)).all()) == 1


def test_deleted_task_rejects_timeline_writes(db_engine):
    with Session(db_engine) as session:
        user, workspace = _workspace(session)
        task = TaskService(session).create(workspace.id, user.id, uuid4(), "追踪")
        task.deleted_at = datetime.now(timezone.utc)
        session.commit()
        with pytest.raises(TaskConflictError) as comment_error:
            add_comment(session, workspace.id, user.id, task.id, "x", uuid4())
        assert comment_error.value.code == "lifecycle_conflict"
        with pytest.raises(TaskConflictError) as delay_error:
            add_delay(session, workspace.id, user.id, task.id, datetime.now(timezone.utc) + timedelta(minutes=2), "NO_TIME", request_id=uuid4())
        assert delay_error.value.code == "lifecycle_conflict"
