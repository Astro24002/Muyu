from __future__ import annotations

from datetime import datetime, timezone
from uuid import uuid4

from sqlalchemy.orm import Session

from app.db.enums import MembershipStatus, TaskApprovalRequestType
from app.db.models import User, Workspace, WorkspaceCursor, WorkspaceMembership
from app.sync.service import SyncService
from app.tasks.approvals import TaskApprovalService
from app.tasks.service import TaskService


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
    return owner, partner, workspace


def test_snapshot_contains_viewer_approvals_and_comments(db_engine) -> None:
    with Session(db_engine) as session:
        owner, partner, workspace = _workspace(session)
        task = TaskService(session).create(workspace.id, owner.id, uuid4(), "Shared", quadrant="Q1")
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
        task = task_service.create(workspace.id, owner.id, uuid4(), "Shared", quadrant="Q1")
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
