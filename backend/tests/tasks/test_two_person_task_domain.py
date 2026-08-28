from __future__ import annotations

from datetime import datetime, timezone
from uuid import uuid4

import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.enums import MembershipStatus, TaskStatus
from app.db.models import TaskComment, User, Workspace, WorkspaceCursor, WorkspaceMembership
from app.tasks.conflicts import TaskConflictError
from app.tasks.numbering import TaskNumberAllocator
from app.tasks.service import TaskService


def _workspace_with_two_users(session: Session) -> tuple[User, User, Workspace]:
    users = [User(phone=f"+1415555{value:04d}") for value in (2671, 2672)]
    workspace = Workspace(name="Shared")
    session.add_all([*users, workspace])
    session.flush()
    session.add_all(
        WorkspaceMembership(
            workspace_id=workspace.id,
            user_id=user.id,
            member_slot=slot,
            status=MembershipStatus.ACTIVE,
            joined_at=datetime.now(timezone.utc),
        )
        for slot, user in enumerate(users, 1)
    )
    session.add(WorkspaceCursor(workspace_id=workspace.id, next_cursor=1))
    session.flush()
    return users[0], users[1], workspace


def test_number_allocator_assigns_monotonic_period_numbers(db_engine) -> None:
    with Session(db_engine) as session:
        at = datetime(2026, 8, 28, tzinfo=timezone.utc)
        allocator = TaskNumberAllocator()
        assert allocator.allocate(session, at) == "26080001"
        assert allocator.allocate(session, at) == "26080002"


def test_task_create_assigns_numbers_and_rejects_nested_subtasks(db_engine) -> None:
    with Session(db_engine) as session:
        user_a, user_b, workspace = _workspace_with_two_users(session)
        service = TaskService(session, now=lambda: datetime(2026, 8, 28, tzinfo=timezone.utc))
        parent = service.create(workspace.id, user_a.id, uuid4(), "Parent")
        child = service.create(workspace.id, user_a.id, uuid4(), "Child", parent_task_id=parent.id)
        assert parent.task_number == "26080001"
        assert child.task_number == "26080002"
        assert child.parent_task_id == parent.id
        with pytest.raises(TaskConflictError, match="subtasks cannot have subtasks"):
            service.create(workspace.id, user_a.id, uuid4(), "Nested", parent_task_id=child.id)


def test_patch_validates_quadrant_progress_and_owner(db_engine) -> None:
    with Session(db_engine) as session:
        user_a, user_b, workspace = _workspace_with_two_users(session)
        service = TaskService(session)
        task = service.create(workspace.id, user_a.id, uuid4(), "Task", assignee_ids=[user_a.id, user_b.id])
        versions = task.field_versions

        task = service.transition(workspace.id, user_a.id, task.id, uuid4(), "IN_PROGRESS", task.status_version)
        versions = task.field_versions
        updated = service.patch(
            workspace.id,
            user_a.id,
            task.id,
            uuid4(),
            {"quadrant": "Q1", "progress": 40},
            {"quadrant": versions["quadrant"], "progress": versions["progress"]},
        )
        assert updated.quadrant.value == "Q1"
        assert updated.progress == 40
        assert service.snapshot(updated)["progress"] == 40

        with pytest.raises(TaskConflictError, match="quadrant"):
            service.patch(
                workspace.id,
                user_a.id,
                task.id,
                uuid4(),
                {"quadrant": "Q5"},
                {"quadrant": updated.field_versions["quadrant"]},
            )
        with pytest.raises(TaskConflictError, match="progress"):
            service.patch(
                workspace.id,
                user_a.id,
                task.id,
                uuid4(),
                {"progress": 30},
                {"progress": updated.field_versions["progress"]},
            )
        with pytest.raises(TaskConflictError) as error:
            service.patch(
                workspace.id,
                user_b.id,
                task.id,
                uuid4(),
                {"title": "Needs approval"},
                {"title": updated.field_versions["title"]},
            )
        assert error.value.code == "approval_required"


def test_progress_is_derived_for_todo_and_done_and_defaults_when_started(db_engine) -> None:
    with Session(db_engine) as session:
        user, _, workspace = _workspace_with_two_users(session)
        service = TaskService(session)
        task = service.create(workspace.id, user.id, uuid4(), "Task")
        assert service.snapshot(task)["progress"] == 0
        task = service.transition(workspace.id, user.id, task.id, uuid4(), "IN_PROGRESS", task.status_version)
        assert task.progress == 20
        task = service.transition(workspace.id, user.id, task.id, uuid4(), "DONE", task.status_version)
        assert service.snapshot(task)["progress"] == 100
        assert task.progress == 20


def test_comment_author_can_soft_delete_comment_and_tombstone_is_retained(db_engine) -> None:
    with Session(db_engine) as session:
        user, _, workspace = _workspace_with_two_users(session)
        service = TaskService(session)
        task = service.create(workspace.id, user.id, uuid4(), "Task")
        comment = service.add_comment(workspace.id, user.id, task.id, "Keep audit")
        deleted = service.delete_comment(workspace.id, user.id, comment.id, uuid4(), comment.version)
        assert deleted.deleted_at is not None
        assert deleted.deleted_by == user.id
        stored = session.scalar(select(TaskComment).where(TaskComment.id == comment.id))
        assert stored is not None
        assert stored.deleted_at is not None
        with pytest.raises(TaskConflictError, match="already deleted"):
            service.delete_comment(workspace.id, user.id, comment.id, uuid4(), comment.version)
