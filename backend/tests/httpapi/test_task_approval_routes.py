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


def test_owner_comment_delete_is_pending_and_comment_author_approves(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    owner_headers = _headers(owner)
    partner_headers = _headers(partner)
    created = client.post(
        "/api/v1/tasks",
        headers=owner_headers,
        json={"request_id": str(uuid4()), "title": "Comment task"},
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
        json={"request_id": str(uuid4()), "title": "Scoped"},
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
