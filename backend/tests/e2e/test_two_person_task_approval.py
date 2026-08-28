from __future__ import annotations

from uuid import uuid4

from fastapi.testclient import TestClient

from app.main import create_app

from tests.httpapi.test_device_readonly_permissions import _headers, _ready_workspace
from tests.httpapi.test_lightweight_routes import FakeSmsProvider


def _client(db_engine) -> TestClient:
    app = create_app()
    app.state.engine = db_engine
    app.state.ready = True
    app.state.sms_provider = FakeSmsProvider()
    return TestClient(app)


def test_two_users_complete_task_approval_and_sync_lifecycle(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    owner_headers = _headers(owner)
    partner_headers = _headers(partner)

    created_response = client.post(
        "/api/v1/tasks",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "title": "Shared task",
            "quadrant": "Q2",
            "assignee_ids": [owner["user"]["id"], partner["user"]["id"]],
        },
    )
    assert created_response.status_code == 201, created_response.text
    task = created_response.json()
    task_id = task["id"]
    workspace_id = task["workspace_id"]
    assert task["task_number"].isdigit()

    pending_response = client.patch(
        f"/api/v1/tasks/{task_id}",
        headers=partner_headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"title": "Partner proposal"},
            "base_field_versions": {"title": task["field_versions"]["title"]},
        },
    )
    assert pending_response.status_code == 202, pending_response.text
    approval = pending_response.json()["approval_request"]
    assert approval["requester_id"] == partner["user"]["id"]
    assert approval["approver_id"] == owner["user"]["id"]

    incoming = client.get(
        f"/api/v1/workspaces/{workspace_id}/approval-requests?box=incoming",
        headers=owner_headers,
    )
    assert incoming.status_code == 200, incoming.text
    assert incoming.json()[0]["id"] == approval["id"]

    approved = client.post(
        f"/api/v1/workspaces/{workspace_id}/approval-requests/{approval['id']}/approve",
        headers=owner_headers,
        json={"request_id": str(uuid4())},
    )
    assert approved.status_code == 200, approved.text
    assert approved.json()["approval_request"]["status"] == "APPROVED"
    assert approved.json()["task"]["title"] == "Partner proposal"

    partner_snapshot = client.get(
        "/api/v1/workspaces/current/snapshot", headers=partner_headers
    )
    assert partner_snapshot.status_code == 200, partner_snapshot.text
    assert partner_snapshot.json()["viewer_user_id"] == partner["user"]["id"]
    assert partner_snapshot.json()["tasks"][0]["title"] == "Partner proposal"

    comment = client.post(
        f"/api/v1/tasks/{task_id}/comments",
        headers=partner_headers,
        json={"request_id": str(uuid4()), "body": "Keep the audit trail"},
    )
    assert comment.status_code == 201, comment.text
    comment_id = comment.json()["id"]
    delete_pending = client.request(
        "DELETE",
        f"/api/v1/tasks/{task_id}/comments/{comment_id}",
        headers=owner_headers,
        json={"request_id": str(uuid4()), "base_version": 1},
    )
    assert delete_pending.status_code == 202, delete_pending.text
    comment_approval = delete_pending.json()["approval_request"]
    assert comment_approval["request_type"] == "COMMENT_DELETE"
    assert comment_approval["approver_id"] == partner["user"]["id"]

    comment_approved = client.post(
        f"/api/v1/workspaces/{workspace_id}/approval-requests/{comment_approval['id']}/approve",
        headers=partner_headers,
        json={"request_id": str(uuid4())},
    )
    assert comment_approved.status_code == 200, comment_approved.text
    assert comment_approved.json()["comment"]["deleted_at"] is not None

    stale = client.patch(
        f"/api/v1/tasks/{task_id}",
        headers=partner_headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"title": "Stale proposal"},
            "base_field_versions": {"title": approved.json()["task"]["field_versions"]["title"]},
        },
    )
    assert stale.status_code == 202, stale.text
    stale_approval = stale.json()["approval_request"]
    owner_edit = client.patch(
        f"/api/v1/tasks/{task_id}",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"title": "Owner wins"},
            "base_field_versions": {"title": approved.json()["task"]["field_versions"]["title"]},
        },
    )
    assert owner_edit.status_code == 200, owner_edit.text
    stale_result = client.post(
        f"/api/v1/workspaces/{workspace_id}/approval-requests/{stale_approval['id']}/approve",
        headers=owner_headers,
        json={"request_id": str(uuid4())},
    )
    assert stale_result.status_code == 409, stale_result.text
    assert stale_result.json()["code"] == "approval_conflicted"

    transfer_pending = client.patch(
        f"/api/v1/tasks/{task_id}",
        headers=partner_headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"description": "Transfer after review"},
            "base_field_versions": {"description": owner_edit.json()["field_versions"]["description"]},
        },
    )
    assert transfer_pending.status_code == 202, transfer_pending.text
    transfer_request = transfer_pending.json()["approval_request"]
    transfer = client.patch(
        f"/api/v1/tasks/{task_id}",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"current_handler_id": partner["user"]["id"]},
            "base_field_versions": {"current_handler_id": owner_edit.json()["field_versions"]["current_handler_id"]},
        },
    )
    assert transfer.status_code == 200, transfer.text
    outgoing = client.get(
        f"/api/v1/workspaces/{workspace_id}/approval-requests?box=outgoing",
        headers=partner_headers,
    )
    assert outgoing.status_code == 200, outgoing.text
    assert next(item for item in outgoing.json() if item["id"] == transfer_request["id"])["status"] == "CANCELLED"

    owner_final = client.get("/api/v1/workspaces/current/snapshot", headers=owner_headers)
    partner_final = client.get("/api/v1/workspaces/current/snapshot", headers=partner_headers)
    assert owner_final.status_code == partner_final.status_code == 200
    assert owner_final.json()["cursor"] == partner_final.json()["cursor"]
    assert owner_final.json()["tasks"] == partner_final.json()["tasks"]
    assert any(item["id"] == comment_id and item["deleted_at"] for item in owner_final.json()["comments"])
    print(
        "two-person task approval smoke: "
        f"task_number={owner_final.json()['tasks'][0]['task_number']} "
        f"request_id={approval['request_id']} "
        f"approval_status={approved.json()['approval_request']['status']} "
        f"final_cursor={owner_final.json()['cursor']}"
    )
