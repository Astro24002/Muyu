from __future__ import annotations

from datetime import datetime, timezone
from uuid import uuid4

import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.enums import (
    MembershipStatus,
    TaskApprovalRequestStatus,
    TaskApprovalRequestType,
    TaskStatus,
    UserStatus,
)
from app.db.models import (
    ActivityEvent,
    TaskApprovalRequest,
    TaskComment,
    TaskHandlerHistory,
    TaskOperation,
    Task,
    TaskStatusHistory,
    User,
    Workspace,
    WorkspaceChangeLog,
    WorkspaceCursor,
    WorkspaceMembership,
)
from app.tasks.approval_schemas import ApprovalRequestCreate
from app.tasks.approvals import TaskApprovalResult, TaskApprovalService
from app.tasks.conflicts import TaskConflictError
from app.tasks.service import TaskService


def _workspace(session: Session, member_count: int = 2, phone_seed: int = 8000) -> tuple[list[User], Workspace]:
    users = [User(phone=f"+1415555{phone_seed + index:04d}") for index in range(member_count)]
    workspace = Workspace(name="Shared")
    session.add_all([*users, workspace])
    session.flush()
    session.add_all(
        WorkspaceMembership(
            workspace_id=workspace.id,
            user_id=user.id,
            member_slot=index + 1,
            status=MembershipStatus.ACTIVE,
            joined_at=datetime.now(timezone.utc),
        )
        for index, user in enumerate(users)
    )
    session.add(WorkspaceCursor(workspace_id=workspace.id, next_cursor=1))
    session.flush()
    return users, workspace


def _task(session: Session, workspace: Workspace, owner: User):
    return TaskService(session).create(
        workspace.id,
        owner.id,
        uuid4(),
        "Original",
        quadrant="Q1",
    )


def _create_update(
    session: Session,
    workspace: Workspace,
    requester: User,
    task_id,
    *,
    request_id=None,
    changes=None,
    base_versions=None,
):
    return TaskApprovalService(session).create(
        workspace.id,
        requester.id,
        request_id or uuid4(),
        task_id,
        TaskApprovalRequestType.TASK_UPDATE,
        changes or {"title": "Proposed"},
        base_versions or {"title": 1},
    )


def test_create_derives_the_only_other_active_member_and_keeps_task_unchanged(db_engine) -> None:
    with Session(db_engine) as session:
        [requester, approver], workspace = _workspace(session)
        task = _task(session, workspace, requester)
        before = TaskService(session).snapshot(task)
        assert "assignee_ids" not in before

        request = _create_update(session, workspace, approver, task.id)

        assert request.status == TaskApprovalRequestStatus.PENDING
        assert request.requester_id == approver.id
        assert request.approver_id == requester.id
        assert TaskService(session).snapshot(task) == before


@pytest.mark.parametrize("member_count", [0, 1])
def test_create_rejects_workspaces_without_exactly_two_active_members(db_engine, member_count: int) -> None:
    with Session(db_engine) as session:
        users, workspace = _workspace(session, member_count)
        if not users:
            requester = User(phone="+14155559999")
            session.add(requester)
            session.flush()
            task_id = uuid4()
        else:
            requester = users[0]
            task_id = TaskService(session).create(workspace.id, requester.id, uuid4(), "Original", quadrant="Q1").id

        with pytest.raises(TaskConflictError) as error:
            _create_update(session, workspace, requester, task_id)

        assert error.value.code == "approval_not_allowed"


def test_create_rejects_self_and_cross_workspace_requests(db_engine) -> None:
    with Session(db_engine) as session:
        [user_a, user_b], workspace = _workspace(session)
        task = _task(session, workspace, user_a)
        service = TaskApprovalService(session)

        with pytest.raises(TaskConflictError) as self_error:
            service.create(
                workspace.id,
                user_a.id,
                uuid4(),
                task.id,
                TaskApprovalRequestType.TASK_UPDATE,
                {"title": "Owner cannot request"},
                {"title": 1},
            )
        assert self_error.value.code == "approval_not_allowed"

        [other_user], other_workspace = _workspace(session, 1, phone_seed=8100)
        with pytest.raises(TaskConflictError) as cross_error:
            service.create(
                other_workspace.id,
                other_user.id,
                uuid4(),
                task.id,
                TaskApprovalRequestType.TASK_UPDATE,
                {"title": "Cross workspace"},
                {"title": 1},
            )
        assert cross_error.value.code == "approval_not_allowed"


def test_request_id_replay_is_immutable_and_mismatch_is_rejected(db_engine) -> None:
    with Session(db_engine) as session:
        [owner, requester], workspace = _workspace(session)
        task = _task(session, workspace, owner)
        request_id = uuid4()
        proposed = {"title": "Proposed"}
        service = TaskApprovalService(session)
        first = service.create(
            workspace.id,
            requester.id,
            request_id,
            task.id,
            TaskApprovalRequestType.TASK_UPDATE,
            proposed,
            {"title": 1},
        )
        first_cursor = service.last_cursor
        proposed["title"] = "Caller mutation"
        replay = service.create(
            workspace.id,
            requester.id,
            request_id,
            task.id,
            TaskApprovalRequestType.TASK_UPDATE,
            {"title": "Proposed"},
            {"title": 1},
        )
        assert replay.id == first.id
        assert replay.proposed_changes == {"title": "Proposed"}
        assert service.last_cursor == first_cursor

        with pytest.raises(TaskConflictError) as reused:
            service.create(
                workspace.id,
                requester.id,
                request_id,
                task.id,
                TaskApprovalRequestType.TASK_UPDATE,
                {"title": "Different"},
                {"title": 1},
            )
        assert reused.value.code == "approval_request_reused"


def test_create_schema_forbids_unknown_fields_and_mismatched_versions() -> None:
    with pytest.raises(ValueError):
        ApprovalRequestCreate(
            request_id=uuid4(),
            task_id=uuid4(),
            request_type=TaskApprovalRequestType.TASK_UPDATE,
            proposed_changes={"title": "x"},
            base_field_versions={},
            unknown="not allowed",
        )
    with pytest.raises(ValueError):
        ApprovalRequestCreate(
            request_id=uuid4(),
            task_id=uuid4(),
            request_type=TaskApprovalRequestType.TASK_UPDATE,
            proposed_changes={"title": "x"},
            base_field_versions={"description": 1},
        )


def test_create_schema_rejects_removed_assignee_approval_type() -> None:
    with pytest.raises(ValueError):
        ApprovalRequestCreate(
            request_id=uuid4(),
            task_id=uuid4(),
            request_type="ASSIGNEE_UPDATE",
            proposed_changes={},
            base_field_versions={},
        )


@pytest.mark.parametrize("invalid_field", ["blocked_reason", "resume_handler_id", "waiting_for_user_id"])
def test_invalid_waiting_approval_is_rejected_before_task_or_request_mutation(
    db_engine, invalid_field: str
) -> None:
    with Session(db_engine) as session:
        [owner, partner], workspace = _workspace(session)
        task = _task(session, workspace, owner)
        before = TaskService(session).snapshot(task)
        request_id = uuid4()
        changes: dict[str, object] = {
            "target_status": "WAITING",
            "blocked_reason": "等待确认",
            "resume_handler_id": str(partner.id),
        }
        if invalid_field == "blocked_reason":
            changes["blocked_reason"] = "  "
        elif invalid_field == "resume_handler_id":
            changes["resume_handler_id"] = "not-a-uuid"
        else:
            changes["waiting_for_user_id"] = str(uuid4())

        with pytest.raises(TaskConflictError) as error:
            TaskApprovalService(session).create(
                workspace.id,
                partner.id,
                request_id,
                task.id,
                TaskApprovalRequestType.STATUS_UPDATE,
                changes,
                {"status_version": task.status_version},
            )

        assert error.value.code == "approval_not_allowed"
        assert TaskService(session).snapshot(task) == before
        assert task.status == TaskStatus.TODO
        assert task.status_version == before["status_version"]
        assert session.scalars(
            select(TaskHandlerHistory).where(TaskHandlerHistory.task_id == task.id)
        ).all() == []
        assert session.scalar(
            select(TaskApprovalRequest).where(TaskApprovalRequest.request_id == request_id)
        ) is None


def test_invalid_persisted_waiting_approval_is_rejected_atomically(db_engine) -> None:
    with Session(db_engine) as session:
        [owner, requester], workspace = _workspace(session)
        task = _task(session, workspace, owner)
        request = TaskApprovalRequest(
            workspace_id=workspace.id,
            task_id=task.id,
            requester_id=requester.id,
            approver_id=owner.id,
            request_type=TaskApprovalRequestType.STATUS_UPDATE,
            proposed_changes={"target_status": "WAITING", "resume_handler_id": str(requester.id)},
            base_field_versions={"status_version": task.status_version},
            request_id=uuid4(),
            status=TaskApprovalRequestStatus.PENDING,
        )
        session.add(request)
        session.flush()
        before = TaskService(session).snapshot(task)
        before_status_history = session.scalars(
            select(TaskStatusHistory).where(TaskStatusHistory.task_id == task.id)
        ).all()
        before_handler_history = session.scalars(
            select(TaskHandlerHistory).where(TaskHandlerHistory.task_id == task.id)
        ).all()

        with pytest.raises(TaskConflictError) as error:
            TaskApprovalService(session).approve(
                workspace.id,
                owner.id,
                request.id,
                uuid4(),
            )

        assert error.value.code == "approval_not_allowed"
        assert request.status == TaskApprovalRequestStatus.PENDING
        assert TaskService(session).snapshot(task) == before
        assert task.status == TaskStatus.TODO
        assert task.status_version == before["status_version"]
        assert session.scalars(
            select(TaskStatusHistory).where(TaskStatusHistory.task_id == task.id)
        ).all() == before_status_history
        assert session.scalars(
            select(TaskHandlerHistory).where(TaskHandlerHistory.task_id == task.id)
        ).all() == before_handler_history


def test_invalid_persisted_status_target_is_rejected_before_mutation(db_engine) -> None:
    with Session(db_engine) as session:
        [owner, requester], workspace = _workspace(session)
        task = _task(session, workspace, owner)
        request = TaskApprovalRequest(
            workspace_id=workspace.id,
            task_id=task.id,
            requester_id=requester.id,
            approver_id=owner.id,
            request_type=TaskApprovalRequestType.STATUS_UPDATE,
            proposed_changes={"target_status": "NOT_A_STATUS"},
            base_field_versions={"status_version": task.status_version},
            request_id=uuid4(),
            status=TaskApprovalRequestStatus.PENDING,
        )
        session.add(request)
        session.flush()
        before = TaskService(session).snapshot(task)

        with pytest.raises(TaskConflictError) as error:
            TaskApprovalService(session).approve(
                workspace.id,
                owner.id,
                request.id,
                uuid4(),
            )

        assert error.value.code == "approval_not_allowed"
        assert request.status == TaskApprovalRequestStatus.PENDING
        assert TaskService(session).snapshot(task) == before


def test_list_filters_incoming_and_outgoing_boxes(db_engine) -> None:
    with Session(db_engine) as session:
        [owner, requester], workspace = _workspace(session)
        task = _task(session, workspace, owner)
        service = TaskApprovalService(session)
        outgoing = _create_update(session, workspace, requester, task.id)

        incoming_for_owner = service.list(workspace.id, owner.id, "incoming")
        outgoing_for_requester = service.list(workspace.id, requester.id, "outgoing")
        assert [row.id for row in incoming_for_owner] == [outgoing.id]
        assert [row.id for row in outgoing_for_requester] == [outgoing.id]
        assert service.list(workspace.id, requester.id, "incoming") == []
        assert service.list(workspace.id, owner.id, "outgoing") == []
        assert {row.id for row in service.list(workspace.id, owner.id)} == {outgoing.id}


def test_approve_requires_derived_active_approver_and_applies_once(db_engine) -> None:
    with Session(db_engine) as session:
        [owner, requester], workspace = _workspace(session)
        task = _task(session, workspace, owner)
        approval = _create_update(session, workspace, requester, task.id)
        service = TaskApprovalService(session)

        with pytest.raises(TaskConflictError) as wrong_actor:
            service.approve(workspace.id, requester.id, approval.id, uuid4())
        assert wrong_actor.value.code == "approval_not_allowed"

        action_request_id = uuid4()
        result = service.approve(workspace.id, owner.id, approval.id, action_request_id)
        assert isinstance(result, TaskApprovalResult)
        assert result.request.status == TaskApprovalRequestStatus.APPROVED
        assert result.task is not None
        assert result.task.title == "Proposed"
        assert result.cursor is not None

        replay = service.approve(workspace.id, owner.id, approval.id, action_request_id)
        assert replay.request.id == approval.id
        assert replay.cursor == result.cursor
        assert session.scalar(select(Task).where(Task.id == task.id)).title == "Proposed"

        with pytest.raises(TaskConflictError) as replay_by_other_actor:
            service.approve(workspace.id, requester.id, approval.id, action_request_id)
        assert replay_by_other_actor.value.code == "approval_not_allowed"

        with pytest.raises(TaskConflictError) as second_action:
            service.approve(workspace.id, owner.id, approval.id, uuid4())
        assert second_action.value.code == "approval_already_resolved"
        assert session.scalar(select(TaskOperation).where(TaskOperation.request_id == approval.id)) is not None


def test_reject_and_cancel_are_one_time_and_do_not_mutate_target(db_engine) -> None:
    with Session(db_engine) as session:
        [owner, requester], workspace = _workspace(session)
        task = _task(session, workspace, owner)
        service = TaskApprovalService(session)
        rejected = _create_update(session, workspace, requester, task.id)
        rejection = service.reject(workspace.id, owner.id, rejected.id, uuid4(), "Not now")
        assert rejection.status == TaskApprovalRequestStatus.REJECTED
        assert rejection.rejection_reason == "Not now"
        assert task.title == "Original"
        with pytest.raises(TaskConflictError) as repeat_reject:
            service.reject(workspace.id, owner.id, rejected.id, uuid4())
        assert repeat_reject.value.code == "approval_already_resolved"

        cancelled = _create_update(session, workspace, requester, task.id)
        action_request_id = uuid4()
        result = service.cancel(workspace.id, requester.id, cancelled.id, action_request_id)
        assert result.status == TaskApprovalRequestStatus.CANCELLED
        assert service.cancel(workspace.id, requester.id, cancelled.id, action_request_id).id == cancelled.id
        with pytest.raises(TaskConflictError) as repeat_cancel:
            service.cancel(workspace.id, requester.id, cancelled.id, uuid4())
        assert repeat_cancel.value.code == "approval_already_resolved"
        assert task.title == "Original"


def test_stale_field_marks_request_conflicted_without_overwriting_new_value(db_engine) -> None:
    with Session(db_engine) as session:
        [owner, requester], workspace = _workspace(session)
        task = _task(session, workspace, owner)
        approval = _create_update(session, workspace, requester, task.id)
        TaskService(session).patch(workspace.id, owner.id, task.id, uuid4(), {"title": "Owner edit"}, {"title": 1})

        with pytest.raises(TaskConflictError) as error:
            TaskApprovalService(session).approve(workspace.id, owner.id, approval.id, uuid4())
        assert error.value.code == "approval_conflicted"
        assert approval.status == TaskApprovalRequestStatus.CONFLICTED
        assert task.title == "Owner edit"


def test_stale_status_approval_is_conflicted_after_task_status_changes(db_engine) -> None:
    with Session(db_engine) as session:
        [owner, requester], workspace = _workspace(session, phone_seed=8200)
        task = _task(session, workspace, owner)
        task = TaskService(session).transition(
            workspace.id,
            owner.id,
            task.id,
            uuid4(),
            "IN_PROGRESS",
            task.status_version,
        )
        approval = TaskApprovalService(session).create(
            workspace.id,
            requester.id,
            uuid4(),
            task.id,
            TaskApprovalRequestType.STATUS_UPDATE,
            {"target_status": "REVIEW"},
            {"status_version": task.status_version},
        )
        task = TaskService(session).transition(
            workspace.id,
            owner.id,
            task.id,
            uuid4(),
            "BLOCKED",
            task.status_version,
            blocked_reason="等待外部确认",
            resume_handler_id=owner.id,
        )

        with pytest.raises(TaskConflictError) as error:
            TaskApprovalService(session).approve(workspace.id, owner.id, approval.id, uuid4())

        assert error.value.code == "approval_conflicted"
        assert approval.status == TaskApprovalRequestStatus.CONFLICTED
        assert approval.rejection_reason == "task status version changed"
        assert task.status == TaskStatus.BLOCKED
        assert task.status_version == 3
        conflict_events = session.scalars(
            select(ActivityEvent).where(
                ActivityEvent.task_id == task.id,
                ActivityEvent.event_type == "APPROVAL_CONFLICTED",
            )
        ).all()
        assert len(conflict_events) == 1
        assert conflict_events[0].payload["approval_request"]["status"] == "CONFLICTED"
        assert conflict_events[0].payload["reason"] == "task status version changed"


def test_stale_pending_requests_can_be_cancelled_after_handler_change(db_engine) -> None:
    with Session(db_engine) as session:
        [owner, requester], workspace = _workspace(session)
        task = _task(session, workspace, owner)
        approval = _create_update(session, workspace, requester, task.id)
        TaskService(session).patch(
            workspace.id,
            owner.id,
            task.id,
            uuid4(),
            {"current_handler_id": requester.id},
            {"current_handler_id": 1},
        )

        count = TaskApprovalService(session).cancel_stale_for_task(workspace.id, task.id, "task handler changed")
        assert count == 1
        assert approval.status == TaskApprovalRequestStatus.CANCELLED
        assert approval.rejection_reason == "task handler changed"
        with pytest.raises(TaskConflictError) as error:
            TaskApprovalService(session).approve(workspace.id, owner.id, approval.id, uuid4())
        assert error.value.code == "approval_already_resolved"


def test_comment_delete_approval_is_approved_by_comment_author(db_engine) -> None:
    with Session(db_engine) as session:
        [owner, author], workspace = _workspace(session)
        task = _task(session, workspace, owner)
        comment = TaskService(session).add_comment(workspace.id, author.id, task.id, "Keep audit")
        service = TaskApprovalService(session)
        approval = service.create(
            workspace.id,
            owner.id,
            uuid4(),
            task.id,
            TaskApprovalRequestType.COMMENT_DELETE,
            {},
            {"version": comment.version},
            comment.id,
        )
        assert approval.approver_id == author.id
        with pytest.raises(TaskConflictError) as wrong_actor:
            service.approve(workspace.id, owner.id, approval.id, uuid4())
        assert wrong_actor.value.code == "approval_not_allowed"
        result = service.approve(workspace.id, author.id, approval.id, uuid4())
        assert result.comment is not None
        assert result.comment.deleted_at is not None
        assert result.comment.deleted_by == author.id


def test_approval_lifecycle_writes_activity_and_workspace_cursor(db_engine) -> None:
    with Session(db_engine) as session:
        [owner, requester], workspace = _workspace(session)
        task = _task(session, workspace, owner)
        service = TaskApprovalService(session)
        request = _create_update(session, workspace, requester, task.id)
        creation_cursor = session.scalar(
            select(WorkspaceChangeLog.cursor).where(WorkspaceChangeLog.resource_id == request.id)
        )
        service.reject(workspace.id, owner.id, request.id, uuid4(), "No")
        lifecycle_cursor = request.resolved_cursor
        assert creation_cursor is not None
        assert lifecycle_cursor is not None
        assert lifecycle_cursor > creation_cursor
        event_types = set(session.scalars(select(ActivityEvent.event_type).where(ActivityEvent.task_id == task.id)))
        assert {"APPROVAL_REQUESTED", "APPROVAL_REJECTED"} <= event_types


def test_handler_transfer_approval_changes_task_handler_to_other_active_member(db_engine) -> None:
    with Session(db_engine) as session:
        [owner, requester], workspace = _workspace(session)
        task = _task(session, workspace, owner)
        assert task.current_handler_id == owner.id
        active_member_ids = set(
            session.scalars(
                select(WorkspaceMembership.user_id).where(
                    WorkspaceMembership.workspace_id == workspace.id,
                    WorkspaceMembership.status == MembershipStatus.ACTIVE,
                )
            ).all()
        )
        assert active_member_ids == {owner.id, requester.id}
        assert requester.id != task.current_handler_id

        service = TaskApprovalService(session)
        request = service.create(
            workspace.id,
            requester.id,
            uuid4(),
            task.id,
            TaskApprovalRequestType.HANDLER_TRANSFER,
            {"current_handler_id": requester.id},
            {"current_handler_id": task.field_versions["current_handler_id"]},
        )

        assert request.requester_id == requester.id
        assert request.approver_id == owner.id
        assert request.request_type == TaskApprovalRequestType.HANDLER_TRANSFER
        assert request.proposed_changes == {"current_handler_id": str(requester.id)}

        result = service.approve(workspace.id, owner.id, request.id, uuid4())

        assert result.request.status == TaskApprovalRequestStatus.APPROVED
        assert result.task is task
        assert task.current_handler_id == requester.id


def test_handler_transfer_approval_is_rejected_during_review(db_engine) -> None:
    with Session(db_engine) as session:
        [owner, requester], workspace = _workspace(session, phone_seed=8300)
        task = _task(session, workspace, owner)
        task = TaskService(session).transition(
            workspace.id,
            owner.id,
            task.id,
            uuid4(),
            "IN_PROGRESS",
            task.status_version,
        )
        task = TaskService(session).transition(
            workspace.id,
            owner.id,
            task.id,
            uuid4(),
            "REVIEW",
            task.status_version,
        )
        before = TaskService(session).snapshot(task)
        request_id = uuid4()

        with pytest.raises(TaskConflictError) as error:
            TaskApprovalService(session).create(
                workspace.id,
                requester.id,
                request_id,
                task.id,
                TaskApprovalRequestType.HANDLER_TRANSFER,
                {"current_handler_id": requester.id},
                {"current_handler_id": task.field_versions["current_handler_id"]},
            )

        assert error.value.code == "approval_not_allowed"
        assert TaskService(session).snapshot(task) == before
        assert session.scalar(
            select(TaskApprovalRequest).where(TaskApprovalRequest.request_id == request_id)
        ) is None


def test_blocked_recovery_approval_uses_stored_handler_and_records_history(db_engine) -> None:
    with Session(db_engine) as session:
        [owner, resume_handler], workspace = _workspace(session)
        task = _task(session, workspace, owner)
        task = TaskService(session).transition(
            workspace.id,
            owner.id,
            task.id,
            uuid4(),
            "BLOCKED",
            task.status_version,
            blocked_reason="等待确认",
            resume_handler_id=resume_handler.id,
        )
        request = TaskApprovalService(session).create(
            workspace.id,
            resume_handler.id,
            uuid4(),
            task.id,
            TaskApprovalRequestType.STATUS_UPDATE,
            {"target_status": "IN_PROGRESS"},
            {"status_version": task.status_version},
        )

        result = TaskApprovalService(session).approve(
            workspace.id,
            owner.id,
            request.id,
            uuid4(),
        )

        assert result.task is task
        assert task.current_handler_id == resume_handler.id
        assert task.field_versions["current_handler_id"] == 2
        assert task.blocked_reason is None
        assert task.resume_handler_id is None
        history = session.scalars(
            select(TaskHandlerHistory).where(TaskHandlerHistory.task_id == task.id)
        ).all()
        assert len(history) == 1
        assert history[0].from_user_id == owner.id
        assert history[0].to_user_id == resume_handler.id


def test_specialized_task_approval_types_delegate_to_owner_task_service(db_engine) -> None:
    with Session(db_engine) as session:
        [owner, requester], workspace = _workspace(session)
        task = _task(session, workspace, owner)
        task = TaskService(session).transition(workspace.id, owner.id, task.id, uuid4(), "IN_PROGRESS", task.status_version)
        service = TaskApprovalService(session)

        quadrant = service.create(
            workspace.id,
            requester.id,
            uuid4(),
            task.id,
            TaskApprovalRequestType.QUADRANT_UPDATE,
            {"quadrant": "Q2"},
            {"quadrant": task.field_versions["quadrant"]},
        )
        assert service.approve(workspace.id, owner.id, quadrant.id, uuid4()).task.quadrant.value == "Q2"

        review = service.create(
            workspace.id,
            requester.id,
            uuid4(),
            task.id,
            TaskApprovalRequestType.STATUS_UPDATE,
            {"target_status": "REVIEW"},
            {"status_version": task.status_version},
        )
        review_result = service.approve(workspace.id, owner.id, review.id, uuid4())
        assert review_result.task.status == TaskStatus.REVIEW
        assert review_result.task.reviewer_user_id == requester.id

        done = TaskService(session).transition(
            workspace.id,
            requester.id,
            task.id,
            uuid4(),
            "DONE",
            review_result.task.status_version,
        )
        assert done.status == TaskStatus.DONE
        assert TaskService(session).snapshot(done)["status"] == "DONE"


def test_task_delete_and_restore_approvals_preserve_lifecycle_rules(db_engine) -> None:
    with Session(db_engine) as session:
        [owner, requester], workspace = _workspace(session)
        task = _task(session, workspace, owner)
        service = TaskApprovalService(session)
        delete_request = service.create(
            workspace.id,
            requester.id,
            uuid4(),
            task.id,
            TaskApprovalRequestType.TASK_DELETE,
            {},
            {"lifecycle_version": task.lifecycle_version},
        )
        deleted = service.approve(workspace.id, owner.id, delete_request.id, uuid4()).task
        assert deleted.deleted_at is not None

        restore_request = service.create(
            workspace.id,
            requester.id,
            uuid4(),
            task.id,
            TaskApprovalRequestType.TASK_RESTORE,
            {},
            {"lifecycle_version": deleted.lifecycle_version},
        )
        restored = service.approve(workspace.id, owner.id, restore_request.id, uuid4()).task
        assert restored.deleted_at is None


def test_approval_rejects_disabled_principal_and_unknown_request(db_engine) -> None:
    with Session(db_engine) as session:
        [owner, requester], workspace = _workspace(session)
        task = _task(session, workspace, owner)
        approval = _create_update(session, workspace, requester, task.id)
        owner.status = UserStatus.DISABLED
        with pytest.raises(TaskConflictError) as disabled:
            TaskApprovalService(session).approve(workspace.id, owner.id, approval.id, uuid4())
        assert disabled.value.code == "approval_not_allowed"
        with pytest.raises(TaskConflictError) as missing:
            TaskApprovalService(session).approve(workspace.id, owner.id, uuid4(), uuid4())
        assert missing.value.code == "approval_not_found"
