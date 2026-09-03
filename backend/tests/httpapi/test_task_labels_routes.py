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


def test_non_owner_label_patch_is_pending_then_applied_as_one_array(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    owner_headers = _headers(owner)
    partner_headers = _headers(partner)
    created = client.post(
        "/api/v1/tasks",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "title": "Label approval",
            "quadrant": "Q2",
            "labels": ["工作", "婚礼"],
        },
    )
    assert created.status_code == 201, created.text
    task = created.json()

    pending = client.patch(
        f"/api/v1/tasks/{task['id']}",
        headers=partner_headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"labels": [" 工作 ", "婚礼", "党员"]},
            "base_field_versions": {"labels": task["field_versions"]["labels"]},
        },
    )
    assert pending.status_code == 202, pending.text
    approval = pending.json()["approval_request"]
    assert approval["request_type"] == "TASK_UPDATE"
    assert approval["proposed_changes"]["labels"] == ["工作", "婚礼", "党员"]
    assert client.get(f"/api/v1/tasks/{task['id']}", headers=owner_headers).json()["labels"] == ["工作", "婚礼"]

    approved = client.post(
        f"/api/v1/workspaces/{task['workspace_id']}/approval-requests/{approval['id']}/approve",
        headers=owner_headers,
        json={"request_id": str(uuid4())},
    )
    assert approved.status_code == 200, approved.text
    assert approved.json()["task"]["quadrant"] == "Q2"
    assert approved.json()["task"]["labels"] == ["工作", "婚礼", "党员"]


def test_deadline_cannot_be_cleared_by_owner_or_partner_over_http(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    created = client.post(
        "/api/v1/tasks",
        headers=_headers(owner),
        json={
            "request_id": str(uuid4()),
            "title": "Deadline is required",
            "quadrant": "Q1",
        },
    )
    assert created.status_code == 201, created.text
    task = created.json()
    due_at = task["due_at"]

    owner_clear = client.patch(
        f"/api/v1/tasks/{task['id']}",
        headers=_headers(owner),
        json={
            "request_id": str(uuid4()),
            "changes": {"due_at": None},
            "base_field_versions": {"due_at": task["field_versions"]["due_at"]},
        },
    )
    assert owner_clear.status_code == 422, owner_clear.text
    assert owner_clear.json()["code"] == "invalid_request"

    partner_clear = client.patch(
        f"/api/v1/tasks/{task['id']}",
        headers=_headers(partner),
        json={
            "request_id": str(uuid4()),
            "changes": {"due_at": None},
            "base_field_versions": {"due_at": task["field_versions"]["due_at"]},
        },
    )
    assert partner_clear.status_code == 403, partner_clear.text
    assert partner_clear.json()["code"] == "approval_not_allowed"
    assert client.get(f"/api/v1/tasks/{task['id']}", headers=_headers(owner)).json()["due_at"] == due_at


def test_stale_label_approval_is_conflicted_without_partial_application(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    owner_headers = _headers(owner)
    partner_headers = _headers(partner)
    created = client.post(
        "/api/v1/tasks",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "title": "Stale labels",
            "quadrant": "Q1",
            "labels": ["工作"],
        },
    )
    task = created.json()
    pending = client.patch(
        f"/api/v1/tasks/{task['id']}",
        headers=partner_headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"labels": ["婚礼"]},
            "base_field_versions": {"labels": task["field_versions"]["labels"]},
        },
    )
    approval = pending.json()["approval_request"]
    owner_edit = client.patch(
        f"/api/v1/tasks/{task['id']}",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"labels": ["党员"]},
            "base_field_versions": {"labels": task["field_versions"]["labels"]},
        },
    )
    assert owner_edit.status_code == 200, owner_edit.text
    assert owner_edit.json()["labels"] == ["党员"]

    conflicted = client.post(
        f"/api/v1/workspaces/{task['workspace_id']}/approval-requests/{approval['id']}/approve",
        headers=owner_headers,
        json={"request_id": str(uuid4())},
    )
    assert conflicted.status_code == 409, conflicted.text
    assert conflicted.json()["code"] == "approval_conflicted"
    assert client.get(f"/api/v1/tasks/{task['id']}", headers=owner_headers).json()["labels"] == ["党员"]
