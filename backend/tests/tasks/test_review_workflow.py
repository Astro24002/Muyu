from __future__ import annotations

from datetime import datetime, timezone
from uuid import uuid4

import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.enums import ConflictStatus, MembershipStatus, Resolution, TaskApprovalRequestStatus, TaskApprovalRequestType, TaskStatus
from app.db.models import ActivityEvent, Task, TaskApprovalRequest, TaskOperation, TaskStatusHistory, User, Workspace, WorkspaceChangeLog, WorkspaceCursor, WorkspaceMembership
from app.tasks.approvals import TaskApprovalError, TaskApprovalService
from app.tasks.conflicts import TaskConflictError
from app.tasks.schemas import TransitionRequest
from app.tasks.service import TaskService
from tests.classification_fixtures import seed_approved_classification


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
    seed_approved_classification(session, workspace.id, users[0].id)
    return users[0], users[1], workspace


def _workspace_with_one_user(session: Session, phone_seed: int = 3674) -> tuple[User, Workspace]:
    user = User(phone=f"+1415555{phone_seed:04d}")
    workspace = Workspace(name="Personal")
    session.add_all([user, workspace])
    session.flush()
    session.add(
        WorkspaceMembership(
            workspace_id=workspace.id,
            user_id=user.id,
            member_slot=1,
            status=MembershipStatus.ACTIVE,
            joined_at=NOW,
        )
    )
    session.add(WorkspaceCursor(workspace_id=workspace.id, next_cursor=1))
    session.flush()
    seed_approved_classification(session, workspace.id, user.id)
    return user, workspace


def _review_task(session: Session, owner: User, workspace: Workspace) -> tuple[Task, TaskService]:
    service = TaskService(session, now=lambda: NOW)
    task = service.create(workspace.id, owner.id, uuid4(), "交付结果", quadrant="Q1", labels=["工作"])
    task = service.transition(workspace.id, owner.id, task.id, uuid4(), "IN_PROGRESS", task.status_version)
    task = service.transition(workspace.id, owner.id, task.id, uuid4(), "REVIEW", task.status_version)
    return task, service


def _in_progress_task(session: Session, owner: User, workspace: Workspace) -> tuple[Task, TaskService]:
    service = TaskService(session, now=lambda: NOW)
    task = service.create(workspace.id, owner.id, uuid4(), "交付结果", quadrant="Q1", labels=["工作"])
    task = service.transition(workspace.id, owner.id, task.id, uuid4(), "IN_PROGRESS", task.status_version)
    return task, service


def _handler_conflict(service: TaskService, workspace: Workspace, task: Task, owner: User, proposed_handler: User):
    with pytest.raises(TaskConflictError) as error:
        service.patch(
            workspace.id,
            owner.id,
            task.id,
            uuid4(),
            {"current_handler_id": proposed_handler.id},
            {"current_handler_id": 0},
        )
    assert error.value.code == "field_conflict"
    assert error.value.conflict
    return error.value.conflict[0]


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


def test_submit_review_creates_one_acceptance_request_and_replays_atomically(db_engine) -> None:
    with Session(db_engine) as session:
        owner, reviewer, workspace = _workspace_with_two_users(session, phone_seed=3672)
        task, _task_service = _in_progress_task(session, owner, workspace)
        request_id = uuid4()
        service = TaskApprovalService(session, now=lambda: NOW)

        result = service.submit_review(
            workspace.id,
            owner.id,
            request_id,
            task.id,
            task.status_version,
        )

        assert result.task is task
        assert task.status == TaskStatus.REVIEW
        assert result.request.status == TaskApprovalRequestStatus.PENDING
        assert result.request.requester_id == owner.id
        assert result.request.approver_id == reviewer.id
        assert result.request.proposed_changes == {
            "target_status": "DONE",
            "review_submission": True,
        }
        assert result.request.request_id == request_id
        assert result.request.base_field_versions == {"status_version": task.status_version}
        assert session.scalar(
            select(TaskApprovalRequest).where(TaskApprovalRequest.task_id == task.id)
        ) is result.request

        operation_count = len(session.scalars(select(TaskOperation).where(TaskOperation.task_id == task.id)).all())
        operation_request_ids = [
            operation.request_id
            for operation in session.scalars(select(TaskOperation).where(TaskOperation.task_id == task.id)).all()
        ]
        assert request_id in operation_request_ids
        assert len(operation_request_ids) == len(set(operation_request_ids))
        replay = service.submit_review(
            workspace.id,
            owner.id,
            request_id,
            task.id,
            task.status_version - 1,
        )
        assert replay.request.id == result.request.id
        assert replay.task.status == TaskStatus.REVIEW
        assert len(session.scalars(select(TaskOperation).where(TaskOperation.task_id == task.id)).all()) == operation_count

        approved = service.approve(workspace.id, reviewer.id, result.request.id, uuid4())
        assert approved.request.status == TaskApprovalRequestStatus.APPROVED
        assert approved.task.status == TaskStatus.DONE


def test_review_rejection_requires_reason_and_returns_task_to_progress(db_engine) -> None:
    with Session(db_engine) as session:
        owner, reviewer, workspace = _workspace_with_two_users(session, phone_seed=3673)
        task, _task_service = _in_progress_task(session, owner, workspace)
        service = TaskApprovalService(session, now=lambda: NOW)
        result = service.submit_review(
            workspace.id,
            owner.id,
            uuid4(),
            task.id,
            task.status_version,
        )

        with pytest.raises(TaskApprovalError, match="reason is required"):
            service.reject(workspace.id, reviewer.id, result.request.id, uuid4())
        assert result.request.status == TaskApprovalRequestStatus.PENDING
        assert task.status == TaskStatus.REVIEW

        rejected = service.reject(
            workspace.id,
            reviewer.id,
            result.request.id,
            uuid4(),
            "  请补充验收材料  ",
        )
        assert rejected.request.status == TaskApprovalRequestStatus.REJECTED
        assert rejected.request.rejection_reason == "请补充验收材料"
        assert rejected.request.reviewed_by == reviewer.id
        assert rejected.task is task
        assert rejected.task.status == TaskStatus.IN_PROGRESS
        assert rejected.task.review_rejection_reason == "请补充验收材料"
        assert rejected.task.reviewed_at == NOW


def test_single_member_cannot_submit_review_or_create_acceptance_request(db_engine) -> None:
    with Session(db_engine) as session:
        owner, workspace = _workspace_with_one_user(session)
        task = TaskService(session, now=lambda: NOW).create(
            workspace.id,
            owner.id,
            uuid4(),
            "单人任务",
            quadrant="Q1",
            labels=["工作"],
        )
        task = TaskService(session, now=lambda: NOW).transition(
            workspace.id,
            owner.id,
            task.id,
            uuid4(),
            "IN_PROGRESS",
            task.status_version,
        )

        with pytest.raises(TaskApprovalError, match="exactly two active"):
            TaskApprovalService(session, now=lambda: NOW).submit_review(
                workspace.id,
                owner.id,
                uuid4(),
                task.id,
                task.status_version,
            )

        assert task.status == TaskStatus.IN_PROGRESS
        assert session.scalars(
            select(TaskApprovalRequest).where(TaskApprovalRequest.task_id == task.id)
        ).all() == []


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


def test_proposed_handler_conflict_is_rejected_during_review_without_mutation(db_engine) -> None:
    with Session(db_engine) as session:
        owner, reviewer, workspace = _workspace_with_two_users(session, phone_seed=3683)
        service = TaskService(session, now=lambda: NOW)
        task = service.create(workspace.id, owner.id, uuid4(), "冲突验收", quadrant="Q1", labels=["工作"])
        conflict = _handler_conflict(service, workspace, task, owner, reviewer)
        task = service.transition(workspace.id, owner.id, task.id, uuid4(), "IN_PROGRESS", task.status_version)
        task = service.transition(workspace.id, owner.id, task.id, uuid4(), "REVIEW", task.status_version)
        before = service.snapshot(task)
        conflict_before = (conflict.status, conflict.resolution, conflict.resolved_by, conflict.resolved_at)

        with pytest.raises(TaskConflictError) as error:
            service.resolve_conflict(
                workspace.id,
                reviewer.id,
                task.id,
                conflict.id,
                uuid4(),
                "proposed",
            )

        assert error.value.code == "invalid_request"
        assert service.snapshot(task) == before
        assert (conflict.status, conflict.resolution, conflict.resolved_by, conflict.resolved_at) == conflict_before
        done = service.transition(workspace.id, reviewer.id, task.id, uuid4(), "DONE", task.status_version)
        assert done.status == TaskStatus.DONE
        assert done.current_handler_id == owner.id


def test_current_handler_conflict_can_be_kept_during_review(db_engine) -> None:
    with Session(db_engine) as session:
        owner, reviewer, workspace = _workspace_with_two_users(session, phone_seed=3685)
        service = TaskService(session, now=lambda: NOW)
        task = service.create(workspace.id, owner.id, uuid4(), "保留当前负责人", quadrant="Q1", labels=["工作"])
        conflict = _handler_conflict(service, workspace, task, owner, reviewer)
        task = service.transition(workspace.id, owner.id, task.id, uuid4(), "IN_PROGRESS", task.status_version)
        task = service.transition(workspace.id, owner.id, task.id, uuid4(), "REVIEW", task.status_version)
        before = service.snapshot(task)

        resolved = service.resolve_conflict(
            workspace.id,
            reviewer.id,
            task.id,
            conflict.id,
            uuid4(),
            "current",
        )

        assert resolved.status == TaskStatus.REVIEW
        assert resolved.current_handler_id == owner.id
        assert resolved.reviewer_user_id == reviewer.id
        assert service.snapshot(resolved) == before
        assert conflict.status == ConflictStatus.RESOLVED
        assert conflict.resolution == Resolution.KEEP_CURRENT
        assert conflict.resolved_by == reviewer.id


def test_proposed_handler_conflict_still_applies_before_review(db_engine) -> None:
    with Session(db_engine) as session:
        owner, reviewer, workspace = _workspace_with_two_users(session, phone_seed=3687)
        service = TaskService(session, now=lambda: NOW)
        task = service.create(workspace.id, owner.id, uuid4(), "非验收阶段转交", quadrant="Q1", labels=["工作"])
        conflict = _handler_conflict(service, workspace, task, owner, reviewer)

        resolved = service.resolve_conflict(
            workspace.id,
            reviewer.id,
            task.id,
            conflict.id,
            uuid4(),
            "proposed",
        )

        assert resolved.status == TaskStatus.TODO
        assert resolved.current_handler_id == reviewer.id
        assert resolved.field_versions["current_handler_id"] == 2
        assert conflict.status == ConflictStatus.RESOLVED
        assert conflict.resolution == Resolution.ACCEPT_PROPOSED


def test_proposed_status_conflict_applies_blocked_transition_once(db_engine) -> None:
    with Session(db_engine) as session:
        owner, _reviewer, workspace = _workspace_with_two_users(session, phone_seed=3715)
        service = TaskService(session, now=lambda: NOW)
        task = service.create(workspace.id, owner.id, uuid4(), "冲突阻塞", quadrant="Q1", labels=["工作"])
        current = service.transition(workspace.id, owner.id, task.id, uuid4(), "IN_PROGRESS", task.status_version)
        request_id = uuid4()

        with pytest.raises(TaskConflictError) as error:
            service.transition(
                workspace.id,
                owner.id,
                task.id,
                request_id,
                "BLOCKED",
                1,
                blocked_reason="等待资料",
                resume_handler_id=owner.id,
            )

        conflict = error.value.conflict[0]
        current_status_version = task.status_version
        current_lifecycle_version = task.lifecycle_version
        resolved = service.resolve_conflict(
            workspace.id,
            owner.id,
            task.id,
            conflict.id,
            uuid4(),
            "proposed",
        )

        assert resolved.status == TaskStatus.BLOCKED
        assert resolved.blocked_reason == "等待资料"
        assert resolved.resume_handler_id == owner.id
        assert resolved.status_version == current_status_version + 1
        assert resolved.lifecycle_version == current_lifecycle_version + 1
        histories = session.scalars(select(TaskStatusHistory).where(TaskStatusHistory.task_id == task.id)).all()
        assert len(histories) == 2
        assert histories[-1].from_status == TaskStatus.IN_PROGRESS
        assert histories[-1].to_status == TaskStatus.BLOCKED
        events = session.scalars(
            select(ActivityEvent).where(
                ActivityEvent.task_id == task.id,
                ActivityEvent.request_id == request_id,
            )
        ).all()
        assert len(events) == 1


def test_proposed_status_conflict_applies_review_return_metadata(db_engine) -> None:
    with Session(db_engine) as session:
        owner, reviewer, workspace = _workspace_with_two_users(session, phone_seed=3716)
        service = TaskService(session, now=lambda: NOW)
        task = service.create(workspace.id, owner.id, uuid4(), "冲突退回", quadrant="Q1", labels=["工作"])
        task = service.transition(workspace.id, owner.id, task.id, uuid4(), "IN_PROGRESS", task.status_version)
        task = service.transition(workspace.id, owner.id, task.id, uuid4(), "REVIEW", task.status_version)
        request_id = uuid4()

        with pytest.raises(TaskConflictError) as error:
            service.transition(
                workspace.id,
                reviewer.id,
                task.id,
                request_id,
                "IN_PROGRESS",
                task.status_version - 1,
                review_rejection_reason="补充截图",
            )

        conflict = error.value.conflict[0]
        current_status_version = task.status_version
        current_lifecycle_version = task.lifecycle_version
        resolution_request_id = uuid4()
        resolved = service.resolve_conflict(
            workspace.id,
            reviewer.id,
            task.id,
            conflict.id,
            resolution_request_id,
            "proposed",
        )

        assert resolved.status == TaskStatus.IN_PROGRESS
        assert resolved.current_handler_id == owner.id
        assert resolved.review_rejection_reason == "补充截图"
        assert resolved.reviewed_at == NOW
        assert resolved.status_version == current_status_version + 1
        assert resolved.lifecycle_version == current_lifecycle_version + 1
        histories = session.scalars(select(TaskStatusHistory).where(TaskStatusHistory.task_id == task.id)).all()
        assert histories[-1].from_status == TaskStatus.REVIEW
        assert histories[-1].to_status == TaskStatus.IN_PROGRESS
        resolution_events = session.scalars(
            select(ActivityEvent).where(
                ActivityEvent.task_id == task.id,
                ActivityEvent.request_id == resolution_request_id,
            )
        ).all()
        assert len(resolution_events) == 1
        assert resolution_events[0].event_type == "CONFLICT_RESOLVED"
        assert resolution_events[0].payload["after"]["status"] == "IN_PROGRESS"
        before_replay = (
            len(session.scalars(select(TaskOperation).where(TaskOperation.task_id == task.id)).all()),
            len(session.scalars(select(ActivityEvent).where(ActivityEvent.task_id == task.id)).all()),
            len(histories),
            len(session.scalars(select(WorkspaceChangeLog).where(WorkspaceChangeLog.workspace_id == workspace.id)).all()),
            session.scalar(select(WorkspaceCursor.next_cursor).where(WorkspaceCursor.workspace_id == workspace.id)),
        )
        replayed = service.resolve_conflict(
            workspace.id,
            reviewer.id,
            task.id,
            conflict.id,
            resolution_request_id,
            "proposed",
        )
        assert replayed.status == TaskStatus.IN_PROGRESS
        assert replayed.review_rejection_reason == "补充截图"
        assert (
            len(session.scalars(select(TaskOperation).where(TaskOperation.task_id == task.id)).all()),
            len(session.scalars(select(ActivityEvent).where(ActivityEvent.task_id == task.id)).all()),
            len(session.scalars(select(TaskStatusHistory).where(TaskStatusHistory.task_id == task.id)).all()),
            len(session.scalars(select(WorkspaceChangeLog).where(WorkspaceChangeLog.workspace_id == workspace.id)).all()),
            session.scalar(select(WorkspaceCursor.next_cursor).where(WorkspaceCursor.workspace_id == workspace.id)),
        ) == before_replay


def test_lifecycle_complete_submits_review(db_engine) -> None:
    with Session(db_engine) as session:
        owner, reviewer, workspace = _workspace_with_two_users(session, phone_seed=3684)
        service = TaskService(session, now=lambda: NOW)
        task = service.create(workspace.id, owner.id, uuid4(), "生命周期交付", quadrant="Q1", labels=["工作"])
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
            labels=["工作"],
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
