from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.enums import MembershipStatus, TaskApprovalRequestType
from app.db.models import ActivityEvent, User, Workspace, WorkspaceChangeLog, WorkspaceCursor, WorkspaceMembership
from app.sync.service import SyncCursorExpired, SyncService
from app.tasks.approvals import TaskApprovalService
from app.tasks.service import TaskService
from tests.classification_fixtures import seed_approved_classification


def _workspace(session: Session) -> tuple[User, User, Workspace]:
    owner = User(phone="+14155558001")
    partner = User(phone="+14155558002")
    workspace = Workspace(name="Sync")
    session.add_all([owner, partner, workspace])
    session.flush()
    session.add_all(
        [
            WorkspaceMembership(workspace_id=workspace.id, user_id=owner.id, member_slot=1, status=MembershipStatus.ACTIVE),
            WorkspaceMembership(workspace_id=workspace.id, user_id=partner.id, member_slot=2, status=MembershipStatus.ACTIVE),
            WorkspaceCursor(workspace_id=workspace.id, next_cursor=1),
        ]
    )
    session.flush()
    seed_approved_classification(session, workspace.id, owner.id)
    return owner, partner, workspace


def test_snapshot_contains_viewer_approvals_and_comments(db_engine) -> None:
    with Session(db_engine) as session:
        owner, partner, workspace = _workspace(session)
        task = TaskService(session).create(workspace.id, owner.id, uuid4(), "Shared", quadrant="Q1", labels=["工作"])
        comment = TaskService(session).add_comment(workspace.id, partner.id, task.id, "Keep")
        approval = TaskApprovalService(session).create(
            workspace.id,
            partner.id,
            uuid4(),
            task.id,
            TaskApprovalRequestType.TASK_UPDATE,
            {"title": "Proposed"},
            {"title": 1},
        )
        snapshot = SyncService(session).snapshot(workspace.id, partner.id)
        assert snapshot["viewer_user_id"] == str(partner.id)
        assert snapshot["approval_requests"][0]["id"] == str(approval.id)
        assert snapshot["comments"][0]["id"] == str(comment.id)
        assert snapshot["comments"][0]["workspace_id"] == str(workspace.id)


def test_approval_and_comment_tombstone_are_typed_changes(db_engine) -> None:
    with Session(db_engine) as session:
        owner, partner, workspace = _workspace(session)
        task_service = TaskService(session)
        task = task_service.create(workspace.id, owner.id, uuid4(), "Shared", quadrant="Q1", labels=["工作"])
        baseline = task_service.last_cursor or 0
        approval = TaskApprovalService(session).create(
            workspace.id,
            partner.id,
            uuid4(),
            task.id,
            TaskApprovalRequestType.TASK_UPDATE,
            {"title": "Proposed"},
            {"title": 1},
        )
        comment = task_service.add_comment(workspace.id, partner.id, task.id, "Delete me")
        task_service.delete_comment(workspace.id, partner.id, comment.id, uuid4(), comment.version)
        changes = SyncService(session).changes(workspace.id, baseline)
        resource_types = [item["resource_type"] for item in changes["changes"]]
        assert "approval_request" in resource_types
        assert "comment" in resource_types
        comment_change = next(item for item in changes["changes"] if item["resource_type"] == "comment")
        assert comment_change["resource"]["deleted_at"] is not None
        assert comment_change["resource"]["workspace_id"] == str(workspace.id)
        assert any(item["resource_id"] == str(approval.id) for item in changes["changes"])


def test_review_and_transfer_content_survive_resolved_sync_changes(db_engine) -> None:
    with Session(db_engine) as session:
        owner, partner, workspace = _workspace(session)
        task_service = TaskService(session, now=lambda: datetime(2026, 9, 2, 12, tzinfo=timezone.utc))
        approval_service = TaskApprovalService(session, now=lambda: datetime(2026, 9, 2, 12, tzinfo=timezone.utc))

        review_task = task_service.create(
            workspace.id,
            owner.id,
            uuid4(),
            "Review sync",
            quadrant="Q1",
            labels=["工作"],
        )
        review_task = task_service.transition(
            workspace.id,
            owner.id,
            review_task.id,
            uuid4(),
            "IN_PROGRESS",
            review_task.status_version,
        )
        baseline = task_service.last_cursor
        assert baseline is not None
        review_request_id = uuid4()
        submitted = approval_service.submit_review(
            workspace.id,
            owner.id,
            review_request_id,
            review_task.id,
            review_task.status_version,
            review_content="已核对交付结果与合同条款",
        )
        assert submitted.cursor is not None

        pending_snapshot = SyncService(session).snapshot(workspace.id, partner.id)
        pending_projection = next(
            item for item in pending_snapshot["approval_requests"] if item["id"] == str(submitted.request.id)
        )
        assert pending_projection["status"] == "PENDING"
        assert pending_projection["proposed_changes"]["review_content"] == "已核对交付结果与合同条款"
        requested_event = next(
            event
            for event in session.scalars(
                select(ActivityEvent).where(ActivityEvent.task_id == review_task.id)
            )
            if event.payload.get("approval_request", {}).get("id") == str(submitted.request.id)
        )
        assert requested_event.payload["approval_request"]["proposed_changes"]["review_content"] == "已核对交付结果与合同条款"

        pending_changes = SyncService(session).changes(workspace.id, baseline)
        pending_change = next(
            item
            for item in pending_changes["changes"]
            if item["resource_type"] == "approval_request"
            and item["resource_id"] == str(submitted.request.id)
        )
        assert pending_change["resource"]["proposed_changes"]["review_content"] == "已核对交付结果与合同条款"

        accepted = approval_service.approve(workspace.id, partner.id, submitted.request.id, uuid4())
        assert accepted.cursor is not None
        resolved_snapshot = SyncService(session).snapshot(workspace.id, owner.id)
        resolved_projection = next(
            item for item in resolved_snapshot["approval_requests"] if item["id"] == str(submitted.request.id)
        )
        assert resolved_projection["status"] == "APPROVED"
        assert resolved_projection["resolved_cursor"] == accepted.cursor
        assert resolved_projection["proposed_changes"]["review_content"] == "已核对交付结果与合同条款"

        resolved_changes = SyncService(session).changes(workspace.id, submitted.cursor)
        resolved_change = next(
            item
            for item in resolved_changes["changes"]
            if item["resource_type"] == "approval_request"
            and item["resource_id"] == str(submitted.request.id)
        )
        assert resolved_change["resource"]["status"] == "APPROVED"
        assert resolved_change["resource"]["resolved_cursor"] == accepted.cursor
        assert resolved_change["resource"]["proposed_changes"]["review_content"] == "已核对交付结果与合同条款"

        transfer_task = task_service.create(
            workspace.id,
            owner.id,
            uuid4(),
            "Transfer sync",
            quadrant="Q2",
            labels=["工作"],
        )
        transfer = approval_service.create(
            workspace.id,
            owner.id,
            uuid4(),
            transfer_task.id,
            TaskApprovalRequestType.HANDLER_TRANSFER,
            {
                "current_handler_id": partner.id,
                "transfer_note": "请继续跟进供应商合同",
            },
            {"current_handler_id": transfer_task.field_versions["current_handler_id"]},
        )
        transfer_created_cursor = approval_service.last_cursor
        assert transfer_created_cursor is not None
        transfer_approved = approval_service.approve(workspace.id, partner.id, transfer.id, uuid4())
        assert transfer_approved.cursor is not None
        transfer_snapshot = SyncService(session).snapshot(workspace.id, owner.id)
        transfer_projection = next(
            item for item in transfer_snapshot["approval_requests"] if item["id"] == str(transfer.id)
        )
        assert transfer_projection["status"] == "APPROVED"
        assert transfer_projection["resolved_cursor"] == transfer_approved.cursor
        assert transfer_projection["proposed_changes"]["transfer_note"] == "请继续跟进供应商合同"
        transfer_changes = SyncService(session).changes(workspace.id, transfer_created_cursor)
        transfer_change = next(
            item
            for item in transfer_changes["changes"]
            if item["resource_type"] == "approval_request"
            and item["resource_id"] == str(transfer.id)
        )
        assert transfer_change["resource"]["status"] == "APPROVED"
        assert transfer_change["resource"]["proposed_changes"]["transfer_note"] == "请继续跟进供应商合同"


def test_changes_reject_expired_cursor_and_middle_cursor_gap(db_engine) -> None:
    with Session(db_engine) as session:
        owner, _partner, workspace = _workspace(session)
        service = TaskService(session)
        task = service.create(workspace.id, owner.id, uuid4(), "Expired sync", quadrant="Q1", labels=["工作"])
        first_cursor = service.last_cursor
        assert first_cursor == 1
        first_log = session.scalar(
            select(WorkspaceChangeLog).where(
                WorkspaceChangeLog.workspace_id == workspace.id,
                WorkspaceChangeLog.cursor == first_cursor,
            )
        )
        assert first_log is not None
        first_log.created_at = datetime.now(timezone.utc) - timedelta(days=31)
        session.flush()
        with pytest.raises(SyncCursorExpired):
            SyncService(session, retention_days=30).changes(workspace.id, 0)

        second = service.create(workspace.id, owner.id, uuid4(), "Gap sync", quadrant="Q1", labels=["工作"])
        third = service.create(workspace.id, owner.id, uuid4(), "Gap sync 2", quadrant="Q1", labels=["工作"])
        assert service.last_cursor == 3
        second_log = session.scalar(
            select(WorkspaceChangeLog).where(
                WorkspaceChangeLog.workspace_id == workspace.id,
                WorkspaceChangeLog.cursor == 2,
            )
        )
        assert second_log is not None
        session.delete(second_log)
        session.flush()
        with pytest.raises(SyncCursorExpired):
            SyncService(session, retention_days=365).changes(workspace.id, 1)
        empty = SyncService(session, retention_days=365).changes(workspace.id, 3)
        assert empty == {"workspace_id": str(workspace.id), "cursor": 3, "changes": []}
