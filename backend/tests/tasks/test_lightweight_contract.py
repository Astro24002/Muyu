from datetime import datetime, timezone
from uuid import uuid4

import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.enums import MembershipStatus
from app.db.models import TaskAssignee, User, Workspace, WorkspaceCursor, WorkspaceMembership
from app.tasks.conflicts import TaskConflictError
from app.tasks.service import TaskService


def _workspace_with_two_users(session):
    users = [User(phone=f"+1415555{n:04d}") for n in (2671, 2672)]
    session.add_all(users)
    workspace = Workspace(name="Shared")
    session.add(workspace)
    session.flush()
    session.add_all([WorkspaceMembership(workspace_id=workspace.id, user_id=u.id, member_slot=i, status=MembershipStatus.ACTIVE, joined_at=datetime.now(timezone.utc)) for i, u in enumerate(users, 1)])
    session.add(WorkspaceCursor(workspace_id=workspace.id, next_cursor=1))
    session.flush()
    return users[0], users[1], workspace


def test_create_one_level_subtask_and_assignees(db_engine):
    with Session(db_engine) as session:
        user_a, user_b, workspace = _workspace_with_two_users(session)
        parent = TaskService(session).create(workspace.id, user_a.id, uuid4(), "父任务")
        child = TaskService(session).create(workspace.id, user_a.id, uuid4(), "子任务", parent_task_id=parent.id, assignee_ids=[user_a.id, user_b.id])
        assert child.parent_task_id == parent.id
        assert set(session.scalars(select(TaskAssignee.user_id).where(TaskAssignee.task_id == child.id))) == {user_a.id, user_b.id}
        with pytest.raises(TaskConflictError) as error:
            TaskService(session).create(workspace.id, user_a.id, uuid4(), "二层", parent_task_id=child.id)
        assert error.value.code == "nested_task_not_allowed"


def test_transition_waiting_done_and_stale_status_creates_conflict(db_engine):
    with Session(db_engine) as session:
        user, _, workspace = _workspace_with_two_users(session)
        task = TaskService(session).create(workspace.id, user.id, uuid4(), "行动")
        TaskService(session).transition(workspace.id, user.id, task.id, uuid4(), "IN_PROGRESS", 1)
        waiting = TaskService(session).transition(workspace.id, user.id, task.id, uuid4(), "WAITING", 2, blocked_reason="等待确认", resume_handler_id=user.id)
        assert waiting.status.value == "WAITING"
        done = TaskService(session).transition(workspace.id, user.id, task.id, uuid4(), "DONE", 3)
        assert TaskService(session).snapshot(done)["status"] == "DONE"
        with pytest.raises(TaskConflictError) as error:
            TaskService(session).transition(workspace.id, user.id, task.id, uuid4(), "TODO", 3)
        assert error.value.code == "field_conflict"
