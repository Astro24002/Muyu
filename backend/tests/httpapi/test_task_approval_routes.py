from __future__ import annotations

from uuid import uuid4

from fastapi.testclient import TestClient
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.db.models import ActivityEvent, TaskOperation, TaskStatusHistory, WorkspaceChangeLog, WorkspaceCursor
from app.main import create_app

from .test_device_readonly_permissions import _headers, _ready_workspace
from .test_lightweight_routes import FakeSmsProvider


def _client(db_engine) -> TestClient:
    app = create_app()
    app.state.engine = db_engine
    app.state.ready = True
    app.state.sms_provider = FakeSmsProvider()
    return TestClient(app)


def _side_effect_counts(db_engine, workspace_id: str, task_id: str) -> tuple[int, int, int, int, int]:
    with Session(db_engine) as session:
        return (
            session.scalar(
                select(func.count()).select_from(TaskOperation).where(TaskOperation.task_id == task_id)
            ),
            session.scalar(
                select(func.count()).select_from(ActivityEvent).where(ActivityEvent.task_id == task_id)
            ),
            session.scalar(
                select(func.count()).select_from(TaskStatusHistory).where(TaskStatusHistory.task_id == task_id)
            ),
            session.scalar(
                select(func.count())
                .select_from(WorkspaceChangeLog)
                .where(WorkspaceChangeLog.workspace_id == workspace_id)
            ),
            session.scalar(
                select(WorkspaceCursor.next_cursor).where(WorkspaceCursor.workspace_id == workspace_id)
            ),
        )


def test_non_owner_patch_creates_pending_approval_and_owner_can_apply(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    owner_headers = _headers(owner)
    partner_headers = _headers(partner)
    created = client.post(
        "/api/v1/tasks",
        headers=owner_headers,
        json={"request_id": str(uuid4()), "title": "Original", "quadrant": "Q2", "labels": ["工作"]},
    )
    assert created.status_code == 201, created.text
    task = created.json()

    pending = client.patch(
        f"/api/v1/tasks/{task['id']}",
        headers=partner_headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"title": "Partner proposal"},
            "base_field_versions": {"title": task["field_versions"]["title"]},
        },
    )
    assert pending.status_code == 202, pending.text
    approval = pending.json()["approval_request"]
    assert pending.json()["pending"] is True
    assert approval["requester_id"] == partner["user"]["id"]
    assert approval["approver_id"] == owner["user"]["id"]

    incoming = client.get(
        f"/api/v1/workspaces/{task['workspace_id']}/approval-requests?box=incoming",
        headers=owner_headers,
    )
    assert incoming.status_code == 200, incoming.text
    assert incoming.json()[0]["id"] == approval["id"]

    approved = client.post(
        f"/api/v1/workspaces/{task['workspace_id']}/approval-requests/{approval['id']}/approve",
        headers=owner_headers,
        json={"request_id": str(uuid4())},
    )
    assert approved.status_code == 200, approved.text
    assert approved.json()["approval_request"]["status"] == "APPROVED"
    assert approved.json()["task"]["title"] == "Partner proposal"


def test_lifecycle_complete_submits_review_and_rejection_returns_task_snapshot(db_engine) -> None:
    client = _client(db_engine)
    owner, reviewer = _ready_workspace(client)
    owner_headers = _headers(owner)
    reviewer_headers = _headers(reviewer)
    created = client.post(
        "/api/v1/tasks",
        headers=owner_headers,
        json={"request_id": str(uuid4()), "title": "Lifecycle review", "quadrant": "Q1", "labels": ["工作"]},
    )
    assert created.status_code == 201, created.text
    task = created.json()
    started = client.post(
        f"/api/v1/tasks/{task['id']}/transition",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "target_status": "IN_PROGRESS",
            "base_status_version": task["status_version"],
        },
    )
    assert started.status_code == 200, started.text

    submitted = client.post(
        f"/api/v1/tasks/{task['id']}/lifecycle",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "action": "complete",
            "base_lifecycle_version": started.json()["lifecycle_version"],
        },
    )
    assert submitted.status_code == 202, submitted.text
    approval = submitted.json()["approval_request"]
    assert submitted.json()["task"]["status"] == "REVIEW"
    assert approval["approver_id"] == reviewer["user"]["id"]

    missing_reason = client.post(
        f"/api/v1/workspaces/{task['workspace_id']}/approval-requests/{approval['id']}/reject",
        headers=reviewer_headers,
        json={"request_id": str(uuid4())},
    )
    assert missing_reason.status_code == 422, missing_reason.text
    assert missing_reason.json()["code"] == "invalid_request"

    rejected = client.post(
        f"/api/v1/workspaces/{task['workspace_id']}/approval-requests/{approval['id']}/reject",
        headers=reviewer_headers,
        json={"request_id": str(uuid4()), "reason": "补充验收材料"},
    )
    assert rejected.status_code == 200, rejected.text
    assert rejected.json()["approval_request"]["status"] == "REJECTED"
    assert rejected.json()["task"]["status"] == "IN_PROGRESS"
    assert rejected.json()["task"]["review_rejection_reason"] == "补充验收材料"


def test_review_handler_conflict_proposed_resolution_cannot_bypass_reviewer_flow(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    owner_headers = _headers(owner)
    partner_headers = _headers(partner)
    created = client.post(
        "/api/v1/tasks",
        headers=owner_headers,
        json={"request_id": str(uuid4()), "title": "Review conflict", "quadrant": "Q1", "labels": ["工作"]},
    )
    assert created.status_code == 201, created.text
    task = created.json()

    stale = client.patch(
        f"/api/v1/tasks/{task['id']}",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"current_handler_id": partner["user"]["id"]},
            "base_field_versions": {"current_handler_id": 0},
        },
    )
    assert stale.status_code == 409, stale.text
    conflict_id = stale.json()["details"]["conflicts"][0]["id"]

    started = client.post(
        f"/api/v1/tasks/{task['id']}/transition",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "target_status": "IN_PROGRESS",
            "base_status_version": task["status_version"],
        },
    )
    assert started.status_code == 200, started.text
    submitted = client.post(
        f"/api/v1/tasks/{task['id']}/transition",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "target_status": "REVIEW",
            "base_status_version": started.json()["status_version"],
        },
    )
    assert submitted.status_code == 202, submitted.text
    submitted_payload = submitted.json()
    before = submitted_payload["task"]
    approval = submitted_payload["approval_request"]

    rejected = client.post(
        f"/api/v1/tasks/{task['id']}/conflicts/{conflict_id}/resolve",
        headers=partner_headers,
        json={"request_id": str(uuid4()), "resolution": "proposed"},
    )
    assert rejected.status_code == 422, rejected.text
    assert rejected.json()["code"] == "invalid_request"

    after_rejection = client.get(f"/api/v1/tasks/{task['id']}", headers=partner_headers)
    assert after_rejection.status_code == 200, after_rejection.text
    assert after_rejection.json()["status"] == "REVIEW"
    assert after_rejection.json()["current_handler_id"] == owner["user"]["id"]
    assert after_rejection.json()["reviewer_user_id"] == partner["user"]["id"]
    assert after_rejection.json()["version"] == before["version"]
    conflicts = client.get(f"/api/v1/tasks/{task['id']}/conflicts", headers=partner_headers)
    assert conflicts.status_code == 200, conflicts.text
    assert conflicts.json()[0]["status"] == "OPEN"

    kept = client.post(
        f"/api/v1/tasks/{task['id']}/conflicts/{conflict_id}/resolve",
        headers=partner_headers,
        json={"request_id": str(uuid4()), "resolution": "current"},
    )
    assert kept.status_code == 200, kept.text
    assert kept.json()["status"] == "REVIEW"
    assert kept.json()["current_handler_id"] == owner["user"]["id"]

    done = client.post(
        f"/api/v1/workspaces/{task['workspace_id']}/approval-requests/{approval['id']}/approve",
        headers=partner_headers,
        json={"request_id": str(uuid4())},
    )
    assert done.status_code == 200, done.text
    assert done.json()["approval_request"]["status"] == "APPROVED"
    assert done.json()["task"]["status"] == "DONE"
    assert done.json()["task"]["current_handler_id"] == owner["user"]["id"]


def test_review_rejection_requires_acceptance_request_and_reason(db_engine) -> None:
    client = _client(db_engine)
    owner, reviewer = _ready_workspace(client)
    owner_headers = _headers(owner)
    reviewer_headers = _headers(reviewer)
    created = client.post(
        "/api/v1/tasks",
        headers=owner_headers,
        json={"request_id": str(uuid4()), "title": "Review 409", "quadrant": "Q1", "labels": ["工作"]},
    ).json()
    started = client.post(
        f"/api/v1/tasks/{created['id']}/transition",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "target_status": "IN_PROGRESS",
            "base_status_version": created["status_version"],
        },
    ).json()
    submitted_response = client.post(
        f"/api/v1/tasks/{created['id']}/transition",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "target_status": "REVIEW",
            "base_status_version": started["status_version"],
        },
    )
    assert submitted_response.status_code == 202, submitted_response.text
    payload = submitted_response.json()
    approval = payload["approval_request"]
    submitted = payload["task"]

    missing_reason = client.post(
        f"/api/v1/tasks/{created['id']}/transition",
        headers=reviewer_headers,
        json={
            "request_id": str(uuid4()),
            "target_status": "IN_PROGRESS",
            "base_status_version": submitted["status_version"],
        },
    )
    assert missing_reason.status_code == 422, missing_reason.text
    assert missing_reason.json()["code"] == "invalid_request"

    rejected = client.post(
        f"/api/v1/workspaces/{created['workspace_id']}/approval-requests/{approval['id']}/reject",
        headers=reviewer_headers,
        json={"request_id": str(uuid4()), "reason": "补充验收材料"},
    )
    assert rejected.status_code == 200, rejected.text
    assert rejected.json()["approval_request"]["status"] == "REJECTED"
    assert rejected.json()["task"]["status"] == "IN_PROGRESS"
    assert rejected.json()["task"]["review_rejection_reason"] == "补充验收材料"


def test_stale_patch_request_replays_the_original_409_across_http_sessions(db_engine) -> None:
    client = _client(db_engine)
    replay_client = _client(db_engine)
    owner, _partner = _ready_workspace(client)
    headers = _headers(owner)
    created = client.post(
        "/api/v1/tasks",
        headers=headers,
        json={"request_id": str(uuid4()), "title": "HTTP replay", "quadrant": "Q1", "labels": ["工作"]},
    )
    assert created.status_code == 201, created.text
    task = created.json()
    changed = client.patch(
        f"/api/v1/tasks/{task['id']}",
        headers=headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"title": "Current title"},
            "base_field_versions": {"title": task["field_versions"]["title"]},
        },
    )
    assert changed.status_code == 200, changed.text

    request_id = str(uuid4())
    body = {
        "request_id": request_id,
        "changes": {"title": "Proposed title"},
        "base_field_versions": {"title": task["field_versions"]["title"]},
    }
    first = client.patch(f"/api/v1/tasks/{task['id']}", headers=headers, json=body)

    assert first.status_code == 409, first.text
    conflict_id = first.json()["details"]["conflicts"][0]["id"]
    resolved = replay_client.post(
        f"/api/v1/tasks/{task['id']}/conflicts/{conflict_id}/resolve",
        headers=headers,
        json={"request_id": str(uuid4()), "resolution": "current"},
    )
    assert resolved.status_code == 200, resolved.text
    before_replay = _side_effect_counts(db_engine, task["workspace_id"], task["id"])
    replay = replay_client.patch(f"/api/v1/tasks/{task['id']}", headers=headers, json=body)
    assert replay.status_code == 409, replay.text
    assert replay.json() == first.json()
    assert _side_effect_counts(db_engine, task["workspace_id"], task["id"]) == before_replay
    assert first.json()["details"]["conflicts"][0]["current_snapshot"]["title"] == "Current title"
    assert isinstance(first.json()["details"]["cursor"], int)


def test_stale_status_request_replays_the_original_409_across_http_sessions(db_engine) -> None:
    client = _client(db_engine)
    replay_client = _client(db_engine)
    owner, _partner = _ready_workspace(client)
    headers = _headers(owner)
    created = client.post(
        "/api/v1/tasks",
        headers=headers,
        json={"request_id": str(uuid4()), "title": "HTTP status replay", "quadrant": "Q1", "labels": ["工作"]},
    ).json()
    started = client.post(
        f"/api/v1/tasks/{created['id']}/transition",
        headers=headers,
        json={
            "request_id": str(uuid4()),
            "target_status": "IN_PROGRESS",
            "base_status_version": created["status_version"],
        },
    )
    assert started.status_code == 200, started.text

    request_id = str(uuid4())
    body = {
        "request_id": request_id,
        "target_status": "BLOCKED",
        "base_status_version": created["status_version"],
        "blocked_reason": "等待资料",
        "resume_handler_id": owner["user"]["id"],
    }
    first = client.post(f"/api/v1/tasks/{created['id']}/transition", headers=headers, json=body)

    assert first.status_code == 409, first.text
    conflict_id = first.json()["details"]["conflicts"][0]["id"]
    resolved = replay_client.post(
        f"/api/v1/tasks/{created['id']}/conflicts/{conflict_id}/resolve",
        headers=headers,
        json={"request_id": str(uuid4()), "resolution": "proposed"},
    )
    assert resolved.status_code == 200, resolved.text
    assert resolved.json()["status"] == "BLOCKED"
    before_replay = _side_effect_counts(db_engine, created["workspace_id"], created["id"])
    replay = replay_client.post(f"/api/v1/tasks/{created['id']}/transition", headers=headers, json=body)
    assert replay.status_code == 409, replay.text
    assert replay.json() == first.json()
    assert _side_effect_counts(db_engine, created["workspace_id"], created["id"]) == before_replay
    assert first.json()["details"]["conflicts"][0]["proposed_payload"]["target_status"] == "BLOCKED"
    assert isinstance(first.json()["details"]["cursor"], int)


def test_conflict_replay_stays_409_after_proposed_handler_transfer_changes_owner(db_engine) -> None:
    client = _client(db_engine)
    replay_client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    owner_headers = _headers(owner)
    partner_headers = _headers(partner)
    created = client.post(
        "/api/v1/tasks",
        headers=owner_headers,
        json={"request_id": str(uuid4()), "title": "Handler replay", "quadrant": "Q1", "labels": ["工作"]},
    ).json()
    transferred = client.patch(
        f"/api/v1/tasks/{created['id']}",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"current_handler_id": partner["user"]["id"]},
            "base_field_versions": {"current_handler_id": 1},
        },
    )
    assert transferred.status_code == 200, transferred.text

    request_id = str(uuid4())
    body = {
        "request_id": request_id,
        "changes": {"current_handler_id": owner["user"]["id"]},
        "base_field_versions": {"current_handler_id": 1},
    }
    first = client.patch(f"/api/v1/tasks/{created['id']}", headers=partner_headers, json=body)
    assert first.status_code == 409, first.text
    conflict_id = first.json()["details"]["conflicts"][0]["id"]

    resolved = replay_client.post(
        f"/api/v1/tasks/{created['id']}/conflicts/{conflict_id}/resolve",
        headers=partner_headers,
        json={"request_id": str(uuid4()), "resolution": "proposed"},
    )
    assert resolved.status_code == 200, resolved.text
    assert resolved.json()["current_handler_id"] == owner["user"]["id"]

    before_replay = _side_effect_counts(db_engine, created["workspace_id"], created["id"])
    replay = replay_client.patch(f"/api/v1/tasks/{created['id']}", headers=partner_headers, json=body)
    assert replay.status_code == 409, replay.text
    assert replay.json() == first.json()
    assert _side_effect_counts(db_engine, created["workspace_id"], created["id"]) == before_replay


def test_stale_blocked_status_409_uses_full_conflict_projection(db_engine) -> None:
    client = _client(db_engine)
    owner, _reviewer = _ready_workspace(client)
    owner_headers = _headers(owner)
    created = client.post(
        "/api/v1/tasks",
        headers=owner_headers,
        json={"request_id": str(uuid4()), "title": "Blocked 409", "quadrant": "Q2", "labels": ["工作"]},
    ).json()
    started = client.post(
        f"/api/v1/tasks/{created['id']}/transition",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "target_status": "IN_PROGRESS",
            "base_status_version": created["status_version"],
        },
    ).json()
    blocked = client.post(
        f"/api/v1/tasks/{created['id']}/transition",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "target_status": "BLOCKED",
            "base_status_version": started["status_version"],
            "blocked_reason": "等待外部材料",
            "resume_handler_id": owner["user"]["id"],
        },
    ).json()

    stale = client.post(
        f"/api/v1/tasks/{created['id']}/transition",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "target_status": "IN_PROGRESS",
            "base_status_version": started["status_version"],
        },
    )
    assert stale.status_code == 409, stale.text
    http_conflict = stale.json()["details"]["conflicts"][0]

    listed = client.get(f"/api/v1/tasks/{created['id']}/conflicts", headers=owner_headers)
    assert listed.status_code == 200, listed.text
    get_conflict = listed.json()[0]
    assert http_conflict == get_conflict
    assert http_conflict["current_snapshot"] == {
        **http_conflict["current_snapshot"],
        "status": "BLOCKED",
        "blocked_reason": "等待外部材料",
        "blocked_since": blocked["blocked_since"],
        "resume_handler_id": owner["user"]["id"],
        "status_version": blocked["status_version"],
        "lifecycle_version": blocked["lifecycle_version"],
    }
    assert http_conflict["status_version"] == blocked["status_version"]
    assert http_conflict["lifecycle_version"] == blocked["lifecycle_version"]
    assert http_conflict["field_versions"] == blocked["field_versions"]


def test_owner_comment_delete_is_pending_and_comment_author_approves(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    owner_headers = _headers(owner)
    partner_headers = _headers(partner)
    created = client.post(
        "/api/v1/tasks",
        headers=owner_headers,
        json={"request_id": str(uuid4()), "title": "Comment task", "quadrant": "Q1", "labels": ["工作"]},
    ).json()
    comment = client.post(
        f"/api/v1/tasks/{created['id']}/comments",
        headers=partner_headers,
        json={"request_id": str(uuid4()), "body": "Audit me"},
    )
    assert comment.status_code == 201, comment.text
    assert comment.json()["workspace_id"] == created["workspace_id"]

    pending = client.request(
        "DELETE",
        f"/api/v1/tasks/{created['id']}/comments/{comment.json()['id']}",
        headers=owner_headers,
        json={"request_id": str(uuid4()), "base_version": 1},
    )
    assert pending.status_code == 202, pending.text
    approval = pending.json()["approval_request"]
    assert approval["request_type"] == "COMMENT_DELETE"
    assert approval["approver_id"] == partner["user"]["id"]

    approved = client.post(
        f"/api/v1/workspaces/{created['workspace_id']}/approval-requests/{approval['id']}/approve",
        headers=partner_headers,
        json={"request_id": str(uuid4())},
    )
    assert approved.status_code == 200, approved.text
    assert approved.json()["comment"]["deleted_at"] is not None


def test_approval_workspace_path_must_match_authenticated_workspace(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    task = client.post(
        "/api/v1/tasks",
        headers=_headers(owner),
        json={"request_id": str(uuid4()), "title": "Scoped", "quadrant": "Q1", "labels": ["工作"]},
    ).json()
    foreign_workspace = uuid4()
    response = client.post(
        f"/api/v1/workspaces/{foreign_workspace}/approval-requests",
        headers=_headers(partner),
        json={
            "request_id": str(uuid4()),
            "task_id": task["id"],
            "request_type": "TASK_UPDATE",
            "proposed_changes": {"title": "Nope"},
            "base_field_versions": {"title": 1},
        },
    )
    assert response.status_code == 403, response.text
    assert response.json()["code"] == "workspace_access_denied"
