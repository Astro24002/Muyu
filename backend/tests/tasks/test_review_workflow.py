from __future__ import annotations

from datetime import datetime, timezone
from uuid import uuid4

import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.enums import MembershipStatus, TaskApprovalRequestStatus, TaskApprovalRequestType, TaskStatus
from app.db.models import ActivityEvent, Task, TaskOperation, TaskStatusHistory, User, Workspace, WorkspaceCursor, WorkspaceMembership
from app.tasks.approvals import TaskApprovalService
from app.tasks.conflicts import TaskConflictError
from app.tasks.schemas import TransitionRequest
from app.tasks.service import TaskService


NOW = datetime(2026, 9, 2, 12, 0, tzinfo=timezone.utc)


def _workspace_with_two_users(session: Session, phone_seed: int = 3671) -> tuple[User, User, Workspace]:
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
    return users[0], users[1], workspace


def _review_task(session: Session, owner: User, workspace: Workspace) -> tuple[Task, TaskService]:
    service = TaskService(session, now=lambda: NOW)
    task = service.create(workspace.id, owner.id, uuid4(), "交付结果", quadrant="Q1")
    task = service.transition(workspace.id, owner.id, task.id, uuid4(), "IN_PROGRESS", task.status_version)
    task = service.transition(workspace.id, owner.id, task.id, uuid4(), "REVIEW", task.status_version)
    return task, service


def test_in_progress_submit_derives_other_active_member_and_preserves_handler(db_engine) -> None:
    with Session(db_engine) as session:
        owner, reviewer, workspace = _workspace_with_two_users(session)
        task, service = _review_task(session, owner, workspace)

        assert task.status == TaskStatus.REVIEW
        assert task.current_handler_id == owner.id
        assert task.reviewer_user_id == reviewer.id
        assert task.review_submitted_at == NOW
        assert task.reviewed_at is None
        assert task.review_rejection_reason is None
        snapshot = service.snapshot(task)
        assert snapshot["status"] == "REVIEW"
        assert snapshot["reviewer_user_id"] == str(reviewer.id)
        assert snapshot["review_submitted_at"] == NOW.isoformat()
        operation = session.scalar(
            select(TaskOperation).where(TaskOperation.task_id == task.id).order_by(TaskOperation.cursor.desc())
        )
        assert operation is not None
        assert operation.after_state["status"] == "REVIEW"
        assert operation.after_state["reviewer_user_id"] == str(reviewer.id)
        assert operation.after_state["review_submitted_at"] == NOW.isoformat()


def test_reviewer_can_accept_review_and_records_reviewed_at(db_engine) -> None:
    with Session(db_engine) as session:
        owner, reviewer, workspace = _workspace_with_two_users(session, phone_seed=3681)
        task, service = _review_task(session, owner, workspace)

        done = service.transition(workspace.id, reviewer.id, task.id, uuid4(), "DONE", task.status_version)

        assert done.status == TaskStatus.DONE
        assert done.current_handler_id == owner.id
        assert done.reviewer_user_id == reviewer.id
        assert done.reviewed_at == NOW
        assert done.review_rejection_reason is None
        snapshot = service.snapshot(done)
        assert snapshot["status"] == "DONE"
        assert snapshot["reviewer_user_id"] == str(reviewer.id)
        assert snapshot["reviewed_at"] == NOW.isoformat()
        history = session.scalars(
            select(TaskStatusHistory).where(TaskStatusHistory.task_id == task.id).order_by(TaskStatusHistory.changed_at)
        ).all()
        assert (history[-1].from_status, history[-1].to_status) == (TaskStatus.REVIEW, TaskStatus.DONE)
        status_events = session.scalars(
            select(ActivityEvent).where(
                ActivityEvent.task_id == task.id,
                ActivityEvent.event_type == "STATUS_CHANGED",
            )
        ).all()
        assert any(event.payload["after"]["status"] == "DONE" for event in status_events)


def test_handler_transfer_is_rejected_during_review_and_reviewer_remains_valid(db_engine) -> None:
    with Session(db_engine) as session:
        owner, reviewer, workspace = _workspace_with_two_users(session, phone_seed=3682)
        task, service = _review_task(session, owner, workspace)
        before = service.snapshot(task)

        with pytest.raises(TaskConflictError) as error:
            service.patch(
                workspace.id,
                owner.id,
                task.id,
                uuid4(),
                {"current_handler_id": reviewer.id},
                {"current_handler_id": task.field_versions["current_handler_id"]},
            )

        assert error.value.code == "invalid_request"
        assert service.snapshot(task) == before
        done = service.transition(workspace.id, reviewer.id, task.id, uuid4(), "DONE", task.status_version)
        assert done.status == TaskStatus.DONE


def test_lifecycle_complete_submits_review(db_engine) -> None:
    with Session(db_engine) as session:
        owner, reviewer, workspace = _workspace_with_two_users(session, phone_seed=3684)
        service = TaskService(session, now=lambda: NOW)
        task = service.create(workspace.id, owner.id, uuid4(), "生命周期交付", quadrant="Q1")
        task = service.transition(workspace.id, owner.id, task.id, uuid4(), "IN_PROGRESS", task.status_version)

        submitted = service.lifecycle(
            workspace.id,
            owner.id,
            task.id,
            uuid4(),
            "complete",
            task.lifecycle_version,
        )

        assert submitted.status == TaskStatus.REVIEW
        assert submitted.current_handler_id == owner.id
        assert submitted.reviewer_user_id == reviewer.id
        assert submitted.review_submitted_at == NOW


def test_review_requires_two_active_members(db_engine) -> None:
    with Session(db_engine) as session:
        owner, reviewer, workspace = _workspace_with_two_users(session, phone_seed=3686)
        task, service = _review_task(session, owner, workspace)
        membership = session.scalar(
            select(WorkspaceMembership).where(
                WorkspaceMembership.workspace_id == workspace.id,
                WorkspaceMembership.user_id == reviewer.id,
            )
        )
        assert membership is not None
        membership.status = MembershipStatus.REVOKED
        session.flush()

        with pytest.raises(TaskConflictError, match="other active workspace member"):
            service.transition(workspace.id, owner.id, task.id, uuid4(), "IN_PROGRESS", task.status_version)


def test_reviewer_return_requires_reason_and_restores_original_handler(db_engine) -> None:
    with Session(db_engine) as session:
        owner, reviewer, workspace = _workspace_with_two_users(session, phone_seed=3691)
        task, service = _review_task(session, owner, workspace)
        review_version = task.status_version

        with pytest.raises(TaskConflictError, match="review_rejection_reason"):
            service.transition(workspace.id, reviewer.id, task.id, uuid4(), "IN_PROGRESS", review_version)
        with pytest.raises(TaskConflictError, match="review_rejection_reason"):
            service.transition(
                workspace.id,
                reviewer.id,
                task.id,
                uuid4(),
            "IN_PROGRESS",
            review_version,
            review_rejection_reason="  ",
            resume_handler_id=reviewer.id,
        )
        assert task.status == TaskStatus.REVIEW
        assert task.status_version == review_version

        with pytest.raises(TaskConflictError) as owner_attempt:
            service.transition(workspace.id, owner.id, task.id, uuid4(), "DONE", review_version)
        assert owner_attempt.value.code == "approval_required"

        return_request_id = uuid4()
        returned = service.transition(
            workspace.id,
            reviewer.id,
            task.id,
            return_request_id,
            "IN_PROGRESS",
            review_version,
            resume_handler_id=reviewer.id,
            review_rejection_reason="  还需要补充订单截图  ",
        )
        assert returned.status == TaskStatus.IN_PROGRESS
        assert returned.current_handler_id == owner.id
        assert returned.reviewer_user_id == reviewer.id
        assert returned.review_submitted_at == NOW
        assert returned.reviewed_at == NOW
        assert returned.review_rejection_reason == "还需要补充订单截图"
        with pytest.raises(TaskConflictError) as reused:
            service.transition(
                workspace.id,
                reviewer.id,
                task.id,
                return_request_id,
                "IN_PROGRESS",
                review_version,
                review_rejection_reason="不同原因",
            )
        assert reused.value.code == "idempotency_key_reused"


def test_resubmission_clears_rejection_and_blocking_clears_review_metadata(db_engine) -> None:
    with Session(db_engine) as session:
        owner, reviewer, workspace = _workspace_with_two_users(session, phone_seed=3701)
        task, service = _review_task(session, owner, workspace)
        task = service.transition(
            workspace.id,
            reviewer.id,
            task.id,
            uuid4(),
            "IN_PROGRESS",
            task.status_version,
            review_rejection_reason="补充材料",
        )
        assert task.review_rejection_reason == "补充材料"
        task = service.transition(workspace.id, owner.id, task.id, uuid4(), "REVIEW", task.status_version)
        assert task.review_rejection_reason is None
        task = service.transition(
            workspace.id,
            reviewer.id,
            task.id,
            uuid4(),
            "IN_PROGRESS",
            task.status_version,
            review_rejection_reason="再次补充材料",
        )

        task = service.transition(
            workspace.id,
            owner.id,
            task.id,
            uuid4(),
            "BLOCKED",
            task.status_version,
            blocked_reason="等待外部文件",
            resume_handler_id=owner.id,
        )
        assert task.status == TaskStatus.BLOCKED
        assert task.reviewer_user_id is None
        assert task.review_submitted_at is None
        assert task.reviewed_at is None
        assert task.review_rejection_reason is None


def test_approval_validation_uses_six_states_and_blocked_review_rules(db_engine) -> None:
    with Session(db_engine) as session:
        owner, requester, workspace = _workspace_with_two_users(session, phone_seed=3711)
        task = TaskService(session, now=lambda: NOW).create(
            workspace.id,
            owner.id,
            uuid4(),
            "待协作任务",
            quadrant="Q4",
        )
        service = TaskApprovalService(session, now=lambda: NOW)

        with pytest.raises(TaskConflictError, match="blocked_reason"):
            service.create(
                workspace.id,
                requester.id,
                uuid4(),
                task.id,
                TaskApprovalRequestType.STATUS_UPDATE,
                {"target_status": "BLOCKED", "resume_handler_id": str(owner.id)},
                {"status_version": task.status_version},
            )

        with pytest.raises(TaskConflictError, match="cannot transition TODO to DONE"):
            service.create(
                workspace.id,
                requester.id,
                uuid4(),
                task.id,
                TaskApprovalRequestType.STATUS_UPDATE,
                {"target_status": "DONE"},
                {"status_version": task.status_version},
            )

        blocked_request = service.create(
            workspace.id,
            requester.id,
            uuid4(),
            task.id,
            TaskApprovalRequestType.STATUS_UPDATE,
            {
                "target_status": "BLOCKED",
                "blocked_reason": "等待确认",
                "resume_handler_id": str(requester.id),
            },
            {"status_version": task.status_version},
        )
        assert blocked_request.status == TaskApprovalRequestStatus.PENDING
        assert blocked_request.proposed_changes["target_status"] == "BLOCKED"
        assert blocked_request.proposed_changes["blocked_reason"] == "等待确认"

        with pytest.raises(TaskConflictError, match="unsupported target status"):
            service.create(
                workspace.id,
                requester.id,
                uuid4(),
                task.id,
                TaskApprovalRequestType.STATUS_UPDATE,
                {"target_status": "WAITING"},
                {"status_version": task.status_version},
            )

        review_request = TransitionRequest(
            request_id=uuid4(),
            target_status="IN_PROGRESS",
            base_status_version=1,
            review_rejection_reason="退回原因",
        )
        assert review_request.review_rejection_reason == "退回原因"
