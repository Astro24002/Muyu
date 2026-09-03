from __future__ import annotations

from uuid import uuid4

from fastapi.testclient import TestClient

from app.main import create_app

from .test_device_readonly_permissions import _headers, _ready_workspace
from .test_lightweight_routes import FakeSmsProvider


def _client(db_engine) -> TestClient:
    app = create_app()
    app.state.engine = db_engine
    app.state.ready = True
    app.state.sms_provider = FakeSmsProvider()
    return TestClient(app)


def test_non_owner_patch_creates_pending_approval_and_owner_can_apply(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    owner_headers = _headers(owner)
    partner_headers = _headers(partner)
    created = client.post(
        "/api/v1/tasks",
        headers=owner_headers,
        json={"request_id": str(uuid4()), "title": "Original", "quadrant": "Q2"},
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


def test_review_handler_conflict_proposed_resolution_cannot_bypass_reviewer_flow(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    owner_headers = _headers(owner)
    partner_headers = _headers(partner)
    created = client.post(
        "/api/v1/tasks",
        headers=owner_headers,
        json={"request_id": str(uuid4()), "title": "Review conflict", "quadrant": "Q1"},
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
    assert submitted.status_code == 200, submitted.text
    before = submitted.json()

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
        f"/api/v1/tasks/{task['id']}/transition",
        headers=partner_headers,
        json={
            "request_id": str(uuid4()),
            "target_status": "DONE",
            "base_status_version": kept.json()["status_version"],
        },
    )
    assert done.status_code == 200, done.text
    assert done.json()["status"] == "DONE"
    assert done.json()["current_handler_id"] == owner["user"]["id"]


def test_stale_review_status_409_uses_full_conflict_projection(db_engine) -> None:
    client = _client(db_engine)
    owner, reviewer = _ready_workspace(client)
    owner_headers = _headers(owner)
    reviewer_headers = _headers(reviewer)
    created = client.post(
        "/api/v1/tasks",
        headers=owner_headers,
        json={"request_id": str(uuid4()), "title": "Review 409", "quadrant": "Q1"},
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
    submitted = client.post(
        f"/api/v1/tasks/{created['id']}/transition",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "target_status": "REVIEW",
            "base_status_version": started["status_version"],
        },
    ).json()

    stale = client.post(
        f"/api/v1/tasks/{created['id']}/transition",
        headers=reviewer_headers,
        json={
            "request_id": str(uuid4()),
            "target_status": "IN_PROGRESS",
            "base_status_version": submitted["status_version"] - 1,
            "review_rejection_reason": "补充验收材料",
        },
    )
    assert stale.status_code == 409, stale.text
    http_conflict = stale.json()["details"]["conflicts"][0]

    listed = client.get(f"/api/v1/tasks/{created['id']}/conflicts", headers=reviewer_headers)
    assert listed.status_code == 200, listed.text
    get_conflict = listed.json()[0]
    assert http_conflict == get_conflict
    assert http_conflict["current_snapshot"] == {
        **http_conflict["current_snapshot"],
        "status": "REVIEW",
        "reviewer_user_id": reviewer["user"]["id"],
        "review_submitted_at": submitted["review_submitted_at"],
        "status_version": submitted["status_version"],
        "lifecycle_version": submitted["lifecycle_version"],
    }
    assert http_conflict["status_version"] == submitted["status_version"]
    assert http_conflict["lifecycle_version"] == submitted["lifecycle_version"]
    assert http_conflict["field_versions"] == submitted["field_versions"]
    assert http_conflict["proposed_payload"]["review_rejection_reason"] == "补充验收材料"


def test_stale_blocked_status_409_uses_full_conflict_projection(db_engine) -> None:
    client = _client(db_engine)
    owner, _reviewer = _ready_workspace(client)
    owner_headers = _headers(owner)
    created = client.post(
        "/api/v1/tasks",
        headers=owner_headers,
        json={"request_id": str(uuid4()), "title": "Blocked 409", "quadrant": "Q2"},
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
        json={"request_id": str(uuid4()), "title": "Comment task", "quadrant": "Q1"},
    ).json()
    comment = client.post(
        f"/api/v1/tasks/{created['id']}/comments",
        headers=partner_headers,
        json={"request_id": str(uuid4()), "body": "Audit me"},
    )
    assert comment.status_code == 201, comment.text

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
        json={"request_id": str(uuid4()), "title": "Scoped", "quadrant": "Q1"},
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
