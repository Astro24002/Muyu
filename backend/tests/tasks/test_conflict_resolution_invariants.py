from __future__ import annotations

from datetime import datetime, timezone
from uuid import uuid4

import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.enums import ChangeAction, ConflictStatus, MembershipStatus, TaskStatus
from app.db.models import (
    ActivityEvent,
    TaskOperation,
    TaskStatusHistory,
    User,
    Workspace,
    WorkspaceChangeLog,
    WorkspaceCursor,
    WorkspaceMembership,
)
from app.tasks.conflicts import TaskConflictError
from app.tasks.service import TaskService


NOW = datetime(2026, 9, 2, 12, 0, tzinfo=timezone.utc)


def _workspace(session: Session) -> tuple[User, User, Workspace]:
    owner = User(phone=f"+1415555{uuid4().int % 10_000_000:07d}")
    reviewer = User(phone=f"+1415555{uuid4().int % 10_000_000:07d}")
    workspace = Workspace(name="Conflict invariants")
    session.add_all([owner, reviewer, workspace])
    session.flush()
    session.add_all(
        [
            WorkspaceMembership(
                workspace_id=workspace.id,
                user_id=owner.id,
                member_slot=1,
                status=MembershipStatus.ACTIVE,
                joined_at=NOW,
            ),
            WorkspaceMembership(
                workspace_id=workspace.id,
                user_id=reviewer.id,
                member_slot=2,
                status=MembershipStatus.ACTIVE,
                joined_at=NOW,
            ),
            WorkspaceCursor(workspace_id=workspace.id, next_cursor=1),
        ]
    )
    session.flush()
    return owner, reviewer, workspace


def test_proposed_status_conflict_is_one_replayable_operation_with_adjacent_cursors(db_engine) -> None:
    with Session(db_engine) as session:
        owner, _reviewer, workspace = _workspace(session)
        service = TaskService(session, now=lambda: NOW)
        task = service.create(workspace.id, owner.id, uuid4(), "状态冲突", quadrant="Q1")
        started = service.transition(
            workspace.id,
            owner.id,
            task.id,
            uuid4(),
            "IN_PROGRESS",
            task.status_version,
        )
        started_status_version = started.status_version
        started_lifecycle_version = started.lifecycle_version
        conflict_request_id = uuid4()
        with pytest.raises(TaskConflictError) as error:
            service.transition(
                workspace.id,
                owner.id,
                task.id,
                conflict_request_id,
                "BLOCKED",
                started.status_version - 1,
                blocked_reason="等待资料",
                resume_handler_id=owner.id,
            )
        conflict = error.value.conflict[0]
        resolution_request_id = uuid4()
        resolved = service.resolve_conflict(
            workspace.id,
            owner.id,
            task.id,
            conflict.id,
            resolution_request_id,
            "proposed",
        )
        assert resolved.status == TaskStatus.BLOCKED
        assert resolved.blocked_reason == "等待资料"
        assert resolved.status_version == started_status_version + 1
        assert resolved.lifecycle_version == started_lifecycle_version + 1

        status_history = session.scalars(
            select(TaskStatusHistory).where(TaskStatusHistory.task_id == task.id)
        ).all()
        assert len(status_history) == 2
        assert {(item.from_status, item.to_status) for item in status_history} == {
            (TaskStatus.TODO, TaskStatus.IN_PROGRESS),
            (TaskStatus.IN_PROGRESS, TaskStatus.BLOCKED),
        }

        resolution_events = session.scalars(
            select(ActivityEvent).where(
                ActivityEvent.task_id == task.id,
                ActivityEvent.request_id == resolution_request_id,
            )
        ).all()
        assert len(resolution_events) == 1
        assert resolution_events[0].event_type == "CONFLICT_RESOLVED"
        assert resolution_events[0].payload["activity_type"] == "TASK_BLOCKED"
        assert resolution_events[0].payload["before"]["status"] == "IN_PROGRESS"
        assert resolution_events[0].payload["after"]["status"] == "BLOCKED"

        operations = session.scalars(
            select(TaskOperation).where(TaskOperation.task_id == task.id)
        ).all()
        assert len(operations) == 4
        assert len({operation.request_id for operation in operations}) == 4
        assert {operation.request_id for operation in operations} >= {
            conflict_request_id,
            resolution_request_id,
        }

        changes = session.scalars(
            select(WorkspaceChangeLog)
            .where(WorkspaceChangeLog.workspace_id == workspace.id)
            .order_by(WorkspaceChangeLog.cursor.asc())
        ).all()
        assert [change.cursor for change in changes] == list(range(1, 7))
        assert [change.action for change in changes] == [
            ChangeAction.CREATED,
            ChangeAction.UPDATED,
            ChangeAction.UPDATED,
            ChangeAction.CREATED,
            ChangeAction.UPDATED,
            ChangeAction.UPDATED,
        ]
        assert [change.operation_id for change in changes[2:4]] == [
            conflict_request_id,
            conflict_request_id,
        ]
        assert [change.operation_id for change in changes[4:6]] == [
            resolution_request_id,
            resolution_request_id,
        ]
        assert changes[2].resource_type == "task"
        assert changes[3].resource_type == "task_conflict"
        assert changes[4].resource_type == "task"
        assert changes[5].resource_type == "task_conflict"
        assert conflict.status == ConflictStatus.RESOLVED
        workspace_id = workspace.id
        owner_id = owner.id
        task_id = task.id
        conflict_id = conflict.id
        session.commit()

    with Session(db_engine) as session:
        replay_service = TaskService(session, now=lambda: NOW)
        replayed = replay_service.resolve_conflict(
            workspace_id,
            owner_id,
            task_id,
            conflict_id,
            resolution_request_id,
            "proposed",
        )
        assert replayed.status == TaskStatus.BLOCKED
        assert replay_service.last_cursor == 6
        assert len(session.scalars(select(TaskStatusHistory).where(TaskStatusHistory.task_id == task_id)).all()) == 2
        assert len(session.scalars(select(ActivityEvent).where(ActivityEvent.task_id == task_id)).all()) == 4
        assert len(session.scalars(select(TaskOperation).where(TaskOperation.task_id == task_id)).all()) == 4
        assert session.scalar(
            select(WorkspaceCursor.next_cursor).where(WorkspaceCursor.workspace_id == workspace_id)
        ) == 7
