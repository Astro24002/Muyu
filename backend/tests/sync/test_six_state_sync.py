from __future__ import annotations

from datetime import datetime, timezone
from uuid import uuid4

import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.enums import ConflictStatus, MembershipStatus, TaskStatus
from app.db.models import ActivityEvent, TaskConflict, User, Workspace, WorkspaceCursor, WorkspaceMembership
from app.sync.service import SyncService
from app.tasks.conflicts import TaskConflictError
from app.tasks.service import TaskService


NOW = datetime(2026, 9, 2, 12, 0, tzinfo=timezone.utc)


def _workspace(session: Session) -> tuple[User, User, Workspace]:
    owner = User(phone=f"+1415555{uuid4().int % 10_000_000:07d}")
    reviewer = User(phone=f"+1415555{uuid4().int % 10_000_000:07d}")
    workspace = Workspace(name="Sync")
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


def test_snapshot_and_cursor_changes_preserve_blocked_projection_and_versions(db_engine) -> None:
    with Session(db_engine) as session:
        owner, _reviewer, workspace = _workspace(session)
        service = TaskService(session, now=lambda: NOW)
        task = service.create(workspace.id, owner.id, uuid4(), "等待文件", quadrant="Q2")
        blocked = service.transition(
            workspace.id,
            owner.id,
            task.id,
            uuid4(),
            "BLOCKED",
            task.status_version,
            blocked_reason="等待外部文件",
            resume_handler_id=owner.id,
            waiting_for_user_id=None,
        )

        snapshot = SyncService(session).snapshot(workspace.id, owner.id)
        projection = next(item for item in snapshot["tasks"] if item["id"] == str(blocked.id))
        assert projection["status"] == "BLOCKED"
        assert projection["blocked_reason"] == "等待外部文件"
        assert projection["blocked_since"] == NOW.isoformat()
        assert projection["resume_handler_id"] == str(owner.id)
        assert projection["waiting_for_user_id"] is None
        assert projection["field_versions"] == blocked.field_versions
        assert projection["status_version"] == blocked.status_version
        assert projection["lifecycle_version"] == blocked.lifecycle_version

        changes = SyncService(session).changes(workspace.id, 0)
        changed_projection = next(
            item["resource"]
            for item in changes["changes"]
            if item["resource_type"] == "task"
            and item["resource_id"] == str(blocked.id)
            and item["resource"] is not None
        )
        assert changed_projection["status"] == "BLOCKED"
        assert changed_projection["blocked_reason"] == "等待外部文件"
        assert changed_projection["status_version"] == blocked.status_version
        assert changed_projection["lifecycle_version"] == blocked.lifecycle_version

        service.transition(
            workspace.id,
            owner.id,
            task.id,
            uuid4(),
            "IN_PROGRESS",
            blocked.status_version,
        )
        event_types = set(
            session.scalars(
                select(ActivityEvent.event_type).where(ActivityEvent.task_id == task.id)
            )
        )
        assert {"TASK_BLOCKED", "TASK_UNBLOCKED"} <= event_types


def test_snapshot_and_cursor_changes_preserve_review_projection_and_versions(db_engine) -> None:
    with Session(db_engine) as session:
        owner, reviewer, workspace = _workspace(session)
        service = TaskService(session, now=lambda: NOW)
        task = service.create(workspace.id, owner.id, uuid4(), "交付结果", quadrant="Q1")
        task = service.transition(workspace.id, owner.id, task.id, uuid4(), "IN_PROGRESS", task.status_version)
        review = service.transition(workspace.id, owner.id, task.id, uuid4(), "REVIEW", task.status_version)

        snapshot = SyncService(session).snapshot(workspace.id, reviewer.id)
        projection = next(item for item in snapshot["tasks"] if item["id"] == str(review.id))
        assert projection["status"] == "REVIEW"
        assert projection["reviewer_user_id"] == str(reviewer.id)
        assert projection["review_submitted_at"] == NOW.isoformat()
        assert projection["reviewed_at"] is None
        assert projection["review_rejection_reason"] is None
        assert projection["field_versions"] == review.field_versions
        assert projection["status_version"] == review.status_version
        assert projection["lifecycle_version"] == review.lifecycle_version

        changes = SyncService(session).changes(workspace.id, 0)
        changed_projection = next(
            item["resource"]
            for item in changes["changes"]
            if item["resource_type"] == "task"
            and item["resource_id"] == str(review.id)
            and item["resource"] is not None
        )
        assert changed_projection["status"] == "REVIEW"
        assert changed_projection["reviewer_user_id"] == str(reviewer.id)
        assert changed_projection["review_submitted_at"] == NOW.isoformat()
        assert changed_projection["status_version"] == review.status_version
        assert changed_projection["lifecycle_version"] == review.lifecycle_version

        returned = service.transition(
            workspace.id,
            reviewer.id,
            review.id,
            uuid4(),
            "IN_PROGRESS",
            review.status_version,
            review_rejection_reason="还需要更多材料",
        )
        assert returned.reviewed_at == NOW
        assert returned.review_rejection_reason == "还需要更多材料"

        resubmitted = service.transition(
            workspace.id,
            owner.id,
            review.id,
            uuid4(),
            "REVIEW",
            returned.status_version,
        )
        done = service.transition(workspace.id, reviewer.id, review.id, uuid4(), "DONE", resubmitted.status_version)
        assert done.reviewed_at == NOW
        assert done.review_rejection_reason is None
        event_types = set(
            session.scalars(
                select(ActivityEvent.event_type).where(ActivityEvent.task_id == task.id)
            )
        )
        assert {
            "TASK_REVIEW_SUBMITTED",
            "TASK_REVIEW_ACCEPTED",
            "TASK_REVIEW_RETURNED",
        } <= event_types


def test_stale_review_conflict_preserves_the_complete_transition_payload(db_engine) -> None:
    with Session(db_engine) as session:
        owner, reviewer, workspace = _workspace(session)
        service = TaskService(session, now=lambda: NOW)
        task = service.create(workspace.id, owner.id, uuid4(), "需要补充材料", quadrant="Q1")
        task = service.transition(workspace.id, owner.id, task.id, uuid4(), "IN_PROGRESS", task.status_version)
        review = service.transition(workspace.id, owner.id, task.id, uuid4(), "REVIEW", task.status_version)
        stale_version = review.status_version - 1

        with pytest.raises(TaskConflictError) as error:
            service.transition(
                workspace.id,
                reviewer.id,
                review.id,
                uuid4(),
                "IN_PROGRESS",
                stale_version,
                review_rejection_reason="还需要订单截图",
            )

        conflict = error.value.conflict[0]
        assert conflict.target == "status"
        assert conflict.status == ConflictStatus.OPEN
        assert conflict.proposed_value["target_status"] == "IN_PROGRESS"
        assert conflict.proposed_value["review_rejection_reason"] == "还需要订单截图"

        synced_conflict = next(
            item for item in SyncService(session).snapshot(workspace.id)["conflicts"]
            if item["id"] == str(conflict.id)
        )
        assert synced_conflict["proposed_payload"]["target_status"] == "IN_PROGRESS"
        assert synced_conflict["proposed_payload"]["review_rejection_reason"] == "还需要订单截图"
        assert synced_conflict["base_version"] == stale_version
        assert synced_conflict["current_version"] == review.status_version
        assert synced_conflict["status_version"] == review.status_version
        assert synced_conflict["lifecycle_version"] == review.lifecycle_version
        assert synced_conflict["field_versions"] == review.field_versions
        assert synced_conflict["current_snapshot"]["reviewer_user_id"] == str(reviewer.id)
        assert synced_conflict["current_snapshot"]["review_submitted_at"] == NOW.isoformat()


def test_stale_blocked_conflict_preserves_blocked_metadata(db_engine) -> None:
    with Session(db_engine) as session:
        owner, _reviewer, workspace = _workspace(session)
        service = TaskService(session, now=lambda: NOW)
        task = service.create(workspace.id, owner.id, uuid4(), "阻塞载荷", quadrant="Q2")
        changed = service.transition(workspace.id, owner.id, task.id, uuid4(), "IN_PROGRESS", task.status_version)

        with pytest.raises(TaskConflictError) as error:
            service.transition(
                workspace.id,
                owner.id,
                task.id,
                uuid4(),
                "BLOCKED",
                1,
                blocked_reason="等待外部确认",
                resume_handler_id=owner.id,
                waiting_for_user_id=None,
            )

        conflict = error.value.conflict[0]
        assert conflict.proposed_value == {
            "target_status": "BLOCKED",
            "blocked_reason": "等待外部确认",
            "resume_handler_id": str(owner.id),
            "waiting_for_user_id": None,
            "review_rejection_reason": None,
        }
        assert conflict.current_version == changed.status_version
