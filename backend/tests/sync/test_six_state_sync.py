from __future__ import annotations

from datetime import datetime, timezone
from uuid import uuid4

import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.enums import ChangeAction, ConflictStatus, MembershipStatus, TaskStatus
from app.db.models import ActivityEvent, TaskConflict, TaskOperation, User, Workspace, WorkspaceChangeLog, WorkspaceCursor, WorkspaceMembership
from app.sync.service import SyncService
from app.tasks.conflicts import TaskConflictError
from app.tasks.service import TaskService


NOW = datetime(2026, 9, 2, 12, 0, tzinfo=timezone.utc)
SIX_STATE_ACTIVITY_METADATA = {
    "field_versions",
    "status_version",
    "lifecycle_version",
    "reviewer_user_id",
    "review_submitted_at",
    "reviewed_at",
    "review_rejection_reason",
    "blocked_reason",
    "blocked_since",
    "resume_handler_id",
    "waiting_for_user_id",
}


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


def _assert_single_status_activity(
    session: Session,
    task_id,
    request_id,
    *,
    activity_type: str,
    activity: str,
    before_status: str,
    after_status: str,
    expected: dict[str, object],
) -> None:
    events = session.scalars(
        select(ActivityEvent).where(
            ActivityEvent.task_id == task_id,
            ActivityEvent.request_id == request_id,
        )
    ).all()
    assert len(events) == 1
    event = events[0]
    assert event.event_type == "STATUS_CHANGED"
    payload = event.payload
    assert payload["activity_type"] == activity_type
    assert payload["activity"] == activity
    assert payload["before"]["status"] == before_status
    assert payload["after"]["status"] == after_status
    assert SIX_STATE_ACTIVITY_METADATA <= payload.keys()
    for key, value in expected.items():
        assert payload[key] == value


def _transition_and_assert_replay(
    service: TaskService,
    session: Session,
    workspace_id,
    task_id,
    actor_user_id,
    request_id,
    target_status: str,
    base_status_version: int,
    *,
    activity_type: str,
    activity: str,
    before_status: str,
    after_status: str,
    expected: dict[str, object],
    **transition_kwargs,
):
    updated = service.transition(
        workspace_id,
        actor_user_id,
        task_id,
        request_id,
        target_status,
        base_status_version,
        **transition_kwargs,
    )
    _assert_single_status_activity(
        session,
        task_id,
        request_id,
        activity_type=activity_type,
        activity=activity,
        before_status=before_status,
        after_status=after_status,
        expected=expected,
    )
    replayed = service.transition(
        workspace_id,
        actor_user_id,
        task_id,
        request_id,
        target_status,
        base_status_version,
        **transition_kwargs,
    )
    assert replayed.id == updated.id
    _assert_single_status_activity(
        session,
        task_id,
        request_id,
        activity_type=activity_type,
        activity=activity,
        before_status=before_status,
        after_status=after_status,
        expected=expected,
    )
    return updated


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
        activity_types = {
            event.payload["activity_type"]
            for event in session.scalars(select(ActivityEvent).where(ActivityEvent.task_id == task.id))
            if "activity_type" in event.payload
        }
        assert activity_types == {"TASK_BLOCKED", "TASK_UNBLOCKED"}


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
        activity_types = {
            event.payload["activity_type"]
            for event in session.scalars(select(ActivityEvent).where(ActivityEvent.task_id == task.id))
            if "activity_type" in event.payload
        }
        assert activity_types == {
            "TASK_REVIEW_SUBMITTED",
            "TASK_REVIEW_ACCEPTED",
            "TASK_REVIEW_RETURNED",
        }


def test_six_state_activities_are_single_append_only_events_and_replays_are_idempotent(db_engine) -> None:
    with Session(db_engine) as session:
        owner, reviewer, workspace = _workspace(session)
        service = TaskService(session, now=lambda: NOW)
        task = service.create(workspace.id, owner.id, uuid4(), "单条活动记录", quadrant="Q1")

        blocked_request_id = uuid4()
        blocked_base_version = task.status_version
        blocked_expected = {
            "status_version": 2,
            "lifecycle_version": 2,
            "reviewer_user_id": None,
            "review_submitted_at": None,
            "reviewed_at": None,
            "review_rejection_reason": None,
            "blocked_reason": "等待外部确认",
            "blocked_since": NOW.isoformat(),
            "resume_handler_id": str(owner.id),
            "waiting_for_user_id": str(reviewer.id),
        }
        blocked = _transition_and_assert_replay(
            service,
            session,
            workspace.id,
            task.id,
            owner.id,
            blocked_request_id,
            "BLOCKED",
            blocked_base_version,
            activity_type="TASK_BLOCKED",
            activity="BLOCKED",
            before_status="TODO",
            after_status="BLOCKED",
            expected=blocked_expected,
            blocked_reason="等待外部确认",
            resume_handler_id=owner.id,
            waiting_for_user_id=reviewer.id,
        )

        unblocked_request_id = uuid4()
        unblocked_base_version = blocked.status_version
        unblocked_expected = {
            "status_version": 3,
            "lifecycle_version": 3,
            "reviewer_user_id": None,
            "review_submitted_at": None,
            "reviewed_at": None,
            "review_rejection_reason": None,
            "blocked_reason": None,
            "blocked_since": None,
            "resume_handler_id": None,
            "waiting_for_user_id": None,
        }
        unblocked = _transition_and_assert_replay(
            service,
            session,
            workspace.id,
            task.id,
            owner.id,
            unblocked_request_id,
            "IN_PROGRESS",
            unblocked_base_version,
            activity_type="TASK_UNBLOCKED",
            activity="UNBLOCKED",
            before_status="BLOCKED",
            after_status="IN_PROGRESS",
            expected=unblocked_expected,
        )

        submitted_request_id = uuid4()
        submitted_base_version = unblocked.status_version
        submitted_expected = {
            "status_version": 4,
            "lifecycle_version": 4,
            "reviewer_user_id": str(reviewer.id),
            "review_submitted_at": NOW.isoformat(),
            "reviewed_at": None,
            "review_rejection_reason": None,
            "blocked_reason": None,
            "blocked_since": None,
            "resume_handler_id": None,
            "waiting_for_user_id": None,
        }
        submitted = _transition_and_assert_replay(
            service,
            session,
            workspace.id,
            task.id,
            owner.id,
            submitted_request_id,
            "REVIEW",
            submitted_base_version,
            activity_type="TASK_REVIEW_SUBMITTED",
            activity="REVIEW_SUBMITTED",
            before_status="IN_PROGRESS",
            after_status="REVIEW",
            expected=submitted_expected,
        )

        returned_request_id = uuid4()
        returned_base_version = submitted.status_version
        returned_expected = {
            "status_version": 5,
            "lifecycle_version": 5,
            "reviewer_user_id": str(reviewer.id),
            "review_submitted_at": NOW.isoformat(),
            "reviewed_at": NOW.isoformat(),
            "review_rejection_reason": "补充订单截图",
            "blocked_reason": None,
            "blocked_since": None,
            "resume_handler_id": None,
            "waiting_for_user_id": None,
        }
        returned = _transition_and_assert_replay(
            service,
            session,
            workspace.id,
            task.id,
            reviewer.id,
            returned_request_id,
            "IN_PROGRESS",
            returned_base_version,
            activity_type="TASK_REVIEW_RETURNED",
            activity="REVIEW_RETURNED",
            before_status="REVIEW",
            after_status="IN_PROGRESS",
            expected=returned_expected,
            review_rejection_reason="补充订单截图",
        )

        resubmitted_request_id = uuid4()
        resubmitted_base_version = returned.status_version
        resubmitted_expected = {
            "status_version": 6,
            "lifecycle_version": 6,
            "reviewer_user_id": str(reviewer.id),
            "review_submitted_at": NOW.isoformat(),
            "reviewed_at": None,
            "review_rejection_reason": None,
            "blocked_reason": None,
            "blocked_since": None,
            "resume_handler_id": None,
            "waiting_for_user_id": None,
        }
        resubmitted = _transition_and_assert_replay(
            service,
            session,
            workspace.id,
            task.id,
            owner.id,
            resubmitted_request_id,
            "REVIEW",
            resubmitted_base_version,
            activity_type="TASK_REVIEW_SUBMITTED",
            activity="REVIEW_SUBMITTED",
            before_status="IN_PROGRESS",
            after_status="REVIEW",
            expected=resubmitted_expected,
        )

        accepted_request_id = uuid4()
        accepted_base_version = resubmitted.status_version
        accepted_expected = {
            "status_version": 7,
            "lifecycle_version": 7,
            "reviewer_user_id": str(reviewer.id),
            "review_submitted_at": NOW.isoformat(),
            "reviewed_at": NOW.isoformat(),
            "review_rejection_reason": None,
            "blocked_reason": None,
            "blocked_since": None,
            "resume_handler_id": None,
            "waiting_for_user_id": None,
        }
        _transition_and_assert_replay(
            service,
            session,
            workspace.id,
            task.id,
            reviewer.id,
            accepted_request_id,
            "DONE",
            accepted_base_version,
            activity_type="TASK_REVIEW_ACCEPTED",
            activity="REVIEW_ACCEPTED",
            before_status="REVIEW",
            after_status="DONE",
            expected=accepted_expected,
        )


def test_stale_review_conflict_preserves_the_complete_transition_payload(db_engine) -> None:
    with Session(db_engine) as session:
        owner, reviewer, workspace = _workspace(session)
        service = TaskService(session, now=lambda: NOW)
        task = service.create(workspace.id, owner.id, uuid4(), "需要补充材料", quadrant="Q1")
        task = service.transition(workspace.id, owner.id, task.id, uuid4(), "IN_PROGRESS", task.status_version)
        review = service.transition(workspace.id, owner.id, task.id, uuid4(), "REVIEW", task.status_version)
        review_cursor = service.last_cursor
        assert review_cursor is not None
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
        conflict_change = next(
            item for item in SyncService(session).changes(workspace.id, review_cursor)["changes"]
            if item["resource_type"] == "task_conflict"
            and item["resource_id"] == str(conflict.id)
        )
        assert conflict_change["action"] == "CREATED"
        assert conflict_change["resource"]["status"] == "OPEN"
        assert conflict_change["resource"]["current_snapshot"]["status"] == "REVIEW"
        assert conflict_change["resource"]["current_snapshot"]["reviewer_user_id"] == str(reviewer.id)


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


def test_conflict_lifecycle_is_cursor_visible_across_sessions_and_idempotent(db_engine) -> None:
    with Session(db_engine) as session:
        owner, _reviewer, workspace = _workspace(session)
        task = TaskService(session, now=lambda: NOW).create(
            workspace.id,
            owner.id,
            uuid4(),
            "冲突游标任务",
            quadrant="Q1",
        )
        session.commit()
        workspace_id = workspace.id
        task_id = task.id
        owner_id = owner.id

    with Session(db_engine) as session:
        current = session.get(type(task), task_id)
        assert current is not None
        TaskService(session, now=lambda: NOW).patch(
            workspace_id,
            owner_id,
            task_id,
            uuid4(),
            {"title": "当前值"},
            {"title": 1},
        )
        session.commit()

    conflict_request_id = uuid4()
    with Session(db_engine) as session:
        cursor_before_conflict = session.scalar(
            select(WorkspaceCursor.next_cursor).where(WorkspaceCursor.workspace_id == workspace_id)
        ) - 1
        service = TaskService(session, now=lambda: NOW)
        with pytest.raises(TaskConflictError) as error:
            service.patch(
                workspace_id,
                owner_id,
                task_id,
                conflict_request_id,
                {"title": "提议值"},
                {"title": 1},
            )
        conflict_id = error.value.conflict[0].id
        session.commit()
        conflict_cursor = session.scalar(
            select(WorkspaceChangeLog.cursor).where(
                WorkspaceChangeLog.workspace_id == workspace_id,
                WorkspaceChangeLog.resource_type == "task_conflict",
                WorkspaceChangeLog.resource_id == conflict_id,
                WorkspaceChangeLog.action == ChangeAction.CREATED,
            )
        )
        assert conflict_cursor is not None
        assert service.last_cursor == conflict_cursor

    with Session(db_engine) as session:
        replay_service = TaskService(session, now=lambda: NOW)
        replayed = replay_service.patch(
            workspace_id,
            owner_id,
            task_id,
            conflict_request_id,
            {"title": "提议值"},
            {"title": 1},
        )
        assert replayed.id == task_id
        assert replay_service.last_cursor == conflict_cursor
        assert session.scalar(
            select(WorkspaceCursor.next_cursor).where(WorkspaceCursor.workspace_id == workspace_id)
        ) - 1 == conflict_cursor

    with Session(db_engine) as session:
        changes = SyncService(session).changes(workspace_id, cursor_before_conflict)
        conflict_changes = [
            item for item in changes["changes"]
            if item["resource_type"] == "task_conflict" and item["resource_id"] == str(conflict_id)
        ]
        assert len(conflict_changes) == 1
        created_projection = conflict_changes[0]
        assert created_projection["action"] == ChangeAction.CREATED.value
        assert created_projection["resource"]["status"] == ConflictStatus.OPEN.value
        assert created_projection["resource"]["current_snapshot"]["status"] == "TODO"
        assert created_projection["resource"]["current_snapshot"]["title"] == "当前值"
        assert created_projection["resource"]["current_snapshot"]["field_versions"]["title"] == 2
        assert created_projection["resource"]["current_snapshot"]["status_version"] == 1
        assert created_projection["resource"]["current_snapshot"]["lifecycle_version"] == 1
        assert created_projection["cursor"] == conflict_cursor

    resolution_request_id = uuid4()
    with Session(db_engine) as session:
        service = TaskService(session, now=lambda: NOW)
        service.resolve_conflict(
            workspace_id,
            owner_id,
            task_id,
            conflict_id,
            resolution_request_id,
            "current",
        )
        session.commit()
        resolved_cursor = service.last_cursor
        assert resolved_cursor is not None
        assert resolved_cursor > conflict_cursor

    with Session(db_engine) as session:
        resolution_changes = SyncService(session).changes(workspace_id, conflict_cursor)
        resolved_projection = next(
            item for item in resolution_changes["changes"]
            if item["resource_type"] == "task_conflict" and item["resource_id"] == str(conflict_id)
        )
        assert resolved_projection["action"] == ChangeAction.UPDATED.value
        assert resolved_projection["resource"]["status"] == ConflictStatus.RESOLVED.value
        assert resolved_projection["resource"]["current_snapshot"]["status"] == "TODO"
        assert resolved_projection["resource"]["current_snapshot"]["title"] == "当前值"
        assert resolution_changes["cursor"] == resolved_cursor

        operations = session.scalars(
            select(TaskOperation).where(
                TaskOperation.workspace_id == workspace_id,
                TaskOperation.request_id.in_([conflict_request_id, resolution_request_id]),
            )
        ).all()
        assert len(operations) == 2
        assert {operation.cursor for operation in operations} == {conflict_cursor, resolved_cursor}
        conflict_logs = session.scalars(
            select(WorkspaceChangeLog).where(
                WorkspaceChangeLog.workspace_id == workspace_id,
                WorkspaceChangeLog.resource_type == "task_conflict",
                WorkspaceChangeLog.resource_id == conflict_id,
            ).order_by(WorkspaceChangeLog.cursor.asc())
        ).all()
        assert [row.action for row in conflict_logs] == [ChangeAction.CREATED, ChangeAction.UPDATED]
        assert [row.cursor for row in conflict_logs] == sorted(row.cursor for row in conflict_logs)

    with Session(db_engine) as session:
        replay_service = TaskService(session, now=lambda: NOW)
        replayed = replay_service.resolve_conflict(
            workspace_id,
            owner_id,
            task_id,
            conflict_id,
            resolution_request_id,
            "current",
        )
        assert replayed.id == task_id
        assert replay_service.last_cursor == resolved_cursor
        assert session.scalar(
            select(WorkspaceCursor.next_cursor).where(WorkspaceCursor.workspace_id == workspace_id)
        ) - 1 == resolved_cursor
