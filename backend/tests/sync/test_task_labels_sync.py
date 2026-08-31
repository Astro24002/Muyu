from __future__ import annotations

from datetime import datetime, timezone
from uuid import uuid4

from sqlalchemy.orm import Session

from app.db.enums import MembershipStatus
from app.db.models import User, Workspace, WorkspaceCursor, WorkspaceMembership
from app.sync.service import SyncService
from app.tasks.service import TaskService


def _workspace(session: Session) -> tuple[User, User, Workspace]:
    owner = User(phone=f"+1415555{uuid4().int % 10_000_000:07d}")
    partner = User(phone=f"+1415555{uuid4().int % 10_000_000:07d}")
    workspace = Workspace(name="Labels sync")
    session.add_all([owner, partner, workspace])
    session.flush()
    session.add_all(
        [
            WorkspaceMembership(workspace_id=workspace.id, user_id=owner.id, member_slot=1, status=MembershipStatus.ACTIVE, joined_at=datetime.now(timezone.utc)),
            WorkspaceMembership(workspace_id=workspace.id, user_id=partner.id, member_slot=2, status=MembershipStatus.ACTIVE, joined_at=datetime.now(timezone.utc)),
            WorkspaceCursor(workspace_id=workspace.id, next_cursor=1),
        ]
    )
    session.flush()
    return owner, partner, workspace


def test_snapshot_and_cursor_changes_round_trip_quadrant_and_labels(db_engine) -> None:
    with Session(db_engine) as session:
        owner, _partner, workspace = _workspace(session)
        service = TaskService(session)
        task = service.create(
            workspace.id,
            owner.id,
            uuid4(),
            "同步任务",
            quadrant="Q2",
            labels=["工作", "婚礼"],
        )
        snapshot = SyncService(session).snapshot(workspace.id, owner.id)
        assert snapshot["tasks"][0]["quadrant"] == "Q2"
        assert snapshot["tasks"][0]["labels"] == ["工作", "婚礼"]

        changes = SyncService(session).changes(workspace.id, 0)
        resource = changes["changes"][0]["resource"]
        assert resource["quadrant"] == "Q2"
        assert resource["labels"] == ["工作", "婚礼"]

        updated = service.patch(
            workspace.id,
            owner.id,
            task.id,
            uuid4(),
            {"labels": ["党员"]},
            {"labels": task.field_versions["labels"]},
        )
        assert updated.labels == ["党员"]
        assert updated.quadrant.value == "Q2"
        updated_snapshot = SyncService(session).snapshot(workspace.id, owner.id)
        assert updated_snapshot["tasks"][0]["labels"] == ["党员"]
        assert updated_snapshot["tasks"][0]["quadrant"] == "Q2"
