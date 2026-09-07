from __future__ import annotations

from datetime import datetime, timezone
from uuid import uuid4

import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.enums import MembershipStatus, TaskApprovalRequestStatus, TaskApprovalRequestType, TaskStatus
from app.db.models import (
    ActivityEvent,
    Task,
    TaskApprovalRequest,
    TaskHandlerHistory,
    TaskStatusHistory,
    User,
    Workspace,
    WorkspaceChangeLog,
    WorkspaceCursor,
    WorkspaceMembership,
)
from app.tasks.approvals import TaskApprovalService
from app.tasks.conflicts import TaskConflictError
from app.tasks.schemas import TransitionRequest
from app.tasks.service import TRANSITIONS, TaskService
from tests.classification_fixtures import seed_approved_classification


NOW = datetime(2026, 9, 2, 12, 0, tzinfo=timezone.utc)


def _workspace_with_two_users(session: Session, phone_seed: int = 2671) -> tuple[User, User, Workspace]:
    users = [User(phone=f"+1415555{value:04d}") for value in (phone_seed, phone_seed + 1)]
    workspace = Workspace(name="Shared")
    session.add_all([*users, workspace])
    session.flush()
    session.add_all(
        WorkspaceMembership(
            workspace_id=workspace.id,
            user_id=user.id,
            member_slot=slot,
            status=MembershipStatus.ACTIVE,
            joined_at=NOW,
        )
        for slot, user in enumerate(users, 1)
    )
    session.add(WorkspaceCursor(workspace_id=workspace.id, next_cursor=1))
    session.flush()
    seed_approved_classification(session, workspace.id, users[0].id)
    return users[0], users[1], workspace


def _service(session: Session) -> TaskService:
    return TaskService(session, now=lambda: NOW)


def test_task_transitions_are_exactly_the_six_state_contract() -> None:
    assert TRANSITIONS == {
        "TODO": {"IN_PROGRESS", "BLOCKED", "CANCELLED"},
        "IN_PROGRESS": {"BLOCKED", "REVIEW", "CANCELLED"},
        "BLOCKED": {"IN_PROGRESS", "CANCELLED"},
        "REVIEW": {"DONE", "IN_PROGRESS", "CANCELLED"},
        "DONE": {"TODO", "IN_PROGRESS", "CANCELLED"},
        "CANCELLED": {"TODO", "IN_PROGRESS"},
    }


def test_transition_request_accepts_review_and_rejects_retired_statuses() -> None:
    request = TransitionRequest(
        request_id=uuid4(),
        target_status="REVIEW",
        base_status_version=1,
        review_rejection_reason="补充材料",
    )
    assert request.target_status == "REVIEW"
    assert request.review_rejection_reason == "补充材料"

    for retired_status in ("WAITING", "COMPLETED"):
        with pytest.raises(ValueError):
            TransitionRequest(
                request_id=uuid4(),
                target_status=retired_status,
                base_status_version=1,
            )


def test_only_current_handler_directly_transitions_normal_tasks_and_blocking_is_reversible(db_engine) -> None:
    with Session(db_engine) as session:
        owner, partner, workspace = _workspace_with_two_users(session)
        service = _service(session)
        task = service.create(workspace.id, owner.id, uuid4(), "等待资料", quadrant="Q2", labels=["工作"])

        with pytest.raises(TaskConflictError) as non_handler:
            service.transition(workspace.id, partner.id, task.id, uuid4(), "IN_PROGRESS", task.status_version)
        assert non_handler.value.code == "approval_required"

        with pytest.raises(TaskConflictError, match="blocked_reason"):
            service.transition(
                workspace.id,
                owner.id,
                task.id,
                uuid4(),
                "BLOCKED",
                task.status_version,
                blocked_reason="  ",
                resume_handler_id=owner.id,
            )

        block_request_id = uuid4()
        blocked = service.transition(
            workspace.id,
            owner.id,
            task.id,
            block_request_id,
            "BLOCKED",
            task.status_version,
            blocked_reason="  等待对方确认  ",
            resume_handler_id=partner.id,
            waiting_for_user_id=partner.id,
        )
        assert blocked.status == TaskStatus.BLOCKED
        assert blocked.current_handler_id == owner.id
        assert blocked.blocked_reason == "等待对方确认"
        assert blocked.blocked_since == NOW
        assert blocked.resume_handler_id == partner.id
        assert blocked.waiting_for_user_id == partner.id
        snapshot = service.snapshot(blocked)
        assert snapshot["status"] == "BLOCKED"
        assert snapshot["blocked_reason"] == "等待对方确认"
        assert snapshot["blocked_since"] == NOW.isoformat()
        assert snapshot["resume_handler_id"] == str(partner.id)
        assert snapshot["waiting_for_user_id"] == str(partner.id)
        assert {
            "reviewer_user_id",
            "review_submitted_at",
            "reviewed_at",
            "review_rejection_reason",
        } <= snapshot.keys()

        with pytest.raises(TaskConflictError, match="cannot transition BLOCKED to DONE"):
            service.transition(workspace.id, owner.id, task.id, uuid4(), "DONE", blocked.status_version)

        replay = service.transition(
            workspace.id,
            owner.id,
            task.id,
            block_request_id,
            "BLOCKED",
            1,
            blocked_reason="  等待对方确认  ",
            resume_handler_id=partner.id,
            waiting_for_user_id=partner.id,
        )
        assert replay.id == blocked.id
        assert service.last_cursor == session.scalar(
            select(WorkspaceChangeLog.cursor).where(
                WorkspaceChangeLog.workspace_id == workspace.id,
                WorkspaceChangeLog.resource_id == task.id,
            ).order_by(WorkspaceChangeLog.cursor.desc())
        )

        resumed = service.transition(
            workspace.id,
            owner.id,
            task.id,
            uuid4(),
            "IN_PROGRESS",
            blocked.status_version,
        )
        assert resumed.status == TaskStatus.IN_PROGRESS
        assert resumed.current_handler_id == partner.id
        assert resumed.blocked_reason is None
        assert resumed.blocked_since is None
        assert resumed.resume_handler_id is None
        assert resumed.waiting_for_user_id is None

        histories = session.scalars(
            select(TaskStatusHistory).where(TaskStatusHistory.task_id == task.id).order_by(TaskStatusHistory.changed_at)
        ).all()
        assert {(item.from_status, item.to_status) for item in histories} == {
            (TaskStatus.TODO, TaskStatus.BLOCKED),
            (TaskStatus.BLOCKED, TaskStatus.IN_PROGRESS),
        }
        handler_history = session.scalars(
            select(TaskHandlerHistory).where(TaskHandlerHistory.task_id == task.id)
        ).all()
        assert len(handler_history) == 1
        assert handler_history[0].from_user_id == owner.id
        assert handler_history[0].to_user_id == partner.id

        status_events = session.scalars(
            select(ActivityEvent).where(
                ActivityEvent.task_id == task.id,
                ActivityEvent.event_type == "STATUS_CHANGED",
            ).order_by(ActivityEvent.created_at)
        ).all()
        assert {event.payload["after"]["status"] for event in status_events} == {
            "BLOCKED",
            "IN_PROGRESS",
        }


def test_status_approval_keeps_non_handler_workflow_and_validates_canonical_statuses(db_engine) -> None:
    with Session(db_engine) as session:
        owner, requester, workspace = _workspace_with_two_users(session, phone_seed=2681)
        task = TaskService(session, now=lambda: NOW).create(
            workspace.id,
            owner.id,
            uuid4(),
            "协作任务",
            quadrant="Q3",
            labels=["工作"],
        )
        service = TaskApprovalService(session, now=lambda: NOW)
        request = service.create(
            workspace.id,
            requester.id,
            uuid4(),
            task.id,
            TaskApprovalRequestType.STATUS_UPDATE,
            {"target_status": "IN_PROGRESS"},
            {"status_version": task.status_version},
        )
        assert request.approver_id == owner.id
        assert request.status == TaskApprovalRequestStatus.PENDING
        assert session.scalar(
            select(TaskApprovalRequest).where(TaskApprovalRequest.id == request.id)
        ) is request
