from datetime import datetime, timezone
from uuid import uuid4

import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.enums import MembershipStatus
from app.db.models import User, Workspace, WorkspaceCursor, WorkspaceMembership
from app.tasks.conflicts import TaskConflictError
from app.tasks.service import TaskService
from tests.classification_fixtures import seed_approved_classification


def _workspace_with_two_users(session):
    users = [User(phone=f"+1415555{n:04d}") for n in (2671, 2672)]
    session.add_all(users)
    workspace = Workspace(name="Shared")
    session.add(workspace)
    session.flush()
    session.add_all([WorkspaceMembership(workspace_id=workspace.id, user_id=u.id, member_slot=i, status=MembershipStatus.ACTIVE, joined_at=datetime.now(timezone.utc)) for i, u in enumerate(users, 1)])
    session.add(WorkspaceCursor(workspace_id=workspace.id, next_cursor=1))
    session.flush()
    seed_approved_classification(session, workspace.id, users[0].id)
    return users[0], users[1], workspace


def test_create_one_level_subtask_uses_only_current_handler(db_engine):
    with Session(db_engine) as session:
        user_a, user_b, workspace = _workspace_with_two_users(session)
        parent = TaskService(session).create(workspace.id, user_a.id, uuid4(), "父任务", quadrant="Q1", labels=["工作"])
        child = TaskService(session).create(workspace.id, user_a.id, uuid4(), "子任务", parent_task_id=parent.id, quadrant="Q1", labels=["工作"])
        assert child.parent_task_id == parent.id
        assert child.current_handler_id == user_a.id
        assert "assignee_ids" not in TaskService(session).snapshot(child)
        with pytest.raises(TaskConflictError) as error:
            TaskService(session).create(workspace.id, user_a.id, uuid4(), "二层", parent_task_id=child.id, quadrant="Q1", labels=["工作"])
        assert error.value.code == "nested_task_not_allowed"


def test_transition_blocked_unblock_and_stale_status_creates_conflict(db_engine):
    with Session(db_engine) as session:
        user, _, workspace = _workspace_with_two_users(session)
        task = TaskService(session).create(workspace.id, user.id, uuid4(), "行动", quadrant="Q1", labels=["工作"])
        TaskService(session).transition(workspace.id, user.id, task.id, uuid4(), "IN_PROGRESS", 1)
        blocked = TaskService(session).transition(workspace.id, user.id, task.id, uuid4(), "BLOCKED", 2, blocked_reason="等待确认", resume_handler_id=user.id)
        assert blocked.status.value == "BLOCKED"
        resumed = TaskService(session).transition(workspace.id, user.id, task.id, uuid4(), "IN_PROGRESS", 3)
        assert TaskService(session).snapshot(resumed)["status"] == "IN_PROGRESS"
        with pytest.raises(TaskConflictError) as error:
            TaskService(session).transition(workspace.id, user.id, task.id, uuid4(), "TODO", 3)
        assert error.value.code == "field_conflict"


def test_transition_replay_keeps_cursor_and_accepts_active_member_as_resume_handler(db_engine):
    with Session(db_engine) as session:
        user_a, user_b, workspace = _workspace_with_two_users(session)
        task = TaskService(session).create(workspace.id, user_a.id, uuid4(), "行动", quadrant="Q1", labels=["工作"])
        request_id = uuid4()
        first_service = TaskService(session)
        started = first_service.transition(workspace.id, user_a.id, task.id, request_id, "IN_PROGRESS", 1)
        first_cursor = first_service.last_cursor
        assert started.status.value == "IN_PROGRESS"
        replay_service = TaskService(session)
        replay = replay_service.transition(workspace.id, user_a.id, task.id, request_id, "IN_PROGRESS", 1)
        assert replay.id == task.id
        assert replay_service.last_cursor == first_cursor
        waiting = TaskService(session).transition(
            workspace.id,
            user_a.id,
            task.id,
            uuid4(),
            "BLOCKED",
            2,
            blocked_reason="等待另一人",
            resume_handler_id=user_b.id,
        )
        assert waiting.resume_handler_id == user_b.id


def test_handler_transfer_replay_returns_stored_result_after_target_member_is_revoked(db_engine):
    with Session(db_engine) as session:
        user_a, user_b, workspace = _workspace_with_two_users(session)
        task = TaskService(session).create(workspace.id, user_a.id, uuid4(), "行动", quadrant="Q1", labels=["工作"])
        request_id = uuid4()
        first_service = TaskService(session)
        first = first_service.patch(
            workspace.id,
            user_a.id,
            task.id,
            request_id,
            {"current_handler_id": str(user_b.id)},
            {"current_handler_id": task.field_versions["current_handler_id"]},
        )
        first_cursor = first_service.last_cursor
        session.commit()

        membership = session.scalar(
            select(WorkspaceMembership).where(
                WorkspaceMembership.workspace_id == workspace.id,
                WorkspaceMembership.user_id == user_b.id,
            )
        )
        assert membership is not None
        membership.status = MembershipStatus.REVOKED
        session.commit()

        replay_service = TaskService(session)
        replay = replay_service.patch(
            workspace.id,
            user_a.id,
            task.id,
            request_id,
            {"current_handler_id": user_b.id},
            {"current_handler_id": 1},
        )

        assert replay.id == first.id
        assert replay.current_handler_id == user_b.id
        assert replay_service.last_cursor == first_cursor


def test_blocked_requires_reason_and_restore_respects_lifecycle_version(db_engine):
    with Session(db_engine) as session:
        user, _, workspace = _workspace_with_two_users(session)
        task = TaskService(session).create(workspace.id, user.id, uuid4(), "行动", quadrant="Q1", labels=["工作"])
        with pytest.raises(TaskConflictError) as error:
            TaskService(session).transition(
                workspace.id,
                user.id,
                task.id,
                uuid4(),
                "BLOCKED",
                1,
                resume_handler_id=user.id,
            )
        assert error.value.code == "invalid_request"

        deleted = TaskService(session).lifecycle(workspace.id, user.id, task.id, uuid4(), "delete", 1)
        assert deleted.deleted_at is not None
        assert deleted.lifecycle_version == 2
        with pytest.raises(TaskConflictError) as error:
            TaskService(session).transition(workspace.id, user.id, task.id, uuid4(), "TODO", deleted.status_version)
        assert error.value.code == "lifecycle_conflict"
        restored = TaskService(session).restore(workspace.id, user.id, task.id, uuid4(), 2)
        assert restored.deleted_at is None
        assert restored.lifecycle_version == 3
        with pytest.raises(TaskConflictError) as error:
            TaskService(session).restore(workspace.id, user.id, task.id, uuid4(), 2)
        assert error.value.code == "lifecycle_conflict"


def test_parent_delete_is_rejected_while_child_is_live(db_engine):
    with Session(db_engine) as session:
        user, _, workspace = _workspace_with_two_users(session)
        parent = TaskService(session).create(workspace.id, user.id, uuid4(), "父任务", quadrant="Q1", labels=["工作"])
        TaskService(session).create(workspace.id, user.id, uuid4(), "子任务", parent_task_id=parent.id, quadrant="Q1", labels=["工作"])
        with pytest.raises(TaskConflictError) as error:
            TaskService(session).lifecycle(workspace.id, user.id, parent.id, uuid4(), "delete", 1)
        assert error.value.code == "lifecycle_conflict"
