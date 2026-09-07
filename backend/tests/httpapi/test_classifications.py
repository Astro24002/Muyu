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


def test_classification_requires_partner_approval_and_syncs_after_approval(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client, seed_classification=False)

    pending = client.post(
        "/api/v1/workspaces/current/classifications",
        headers=_headers(owner),
        json={"request_id": str(uuid4()), "name": "工作"},
    )
    assert pending.status_code == 202, pending.text
    approval = pending.json()["approval_request"]
    assert approval["request_type"] == "CLASSIFICATION_CREATE"
    assert approval["task_id"] is None
    assert client.get(
        "/api/v1/workspaces/current/classifications", headers=_headers(owner)
    ).json() == []

    approved = client.post(
        f"/api/v1/workspaces/{approval['workspace_id']}/approval-requests/{approval['id']}/approve",
        headers=_headers(partner),
        json={"request_id": str(uuid4())},
    )
    assert approved.status_code == 200, approved.text
    assert approved.json()["classification"]["name"] == "工作"

    classifications = client.get(
        "/api/v1/workspaces/current/classifications", headers=_headers(owner)
    )
    assert classifications.status_code == 200, classifications.text
    assert [item["name"] for item in classifications.json()] == ["工作"]

    task = client.post(
        "/api/v1/tasks",
        headers=_headers(owner),
        json={
            "request_id": str(uuid4()),
            "title": "分类任务",
            "quadrant": "Q1",
            "labels": ["工作"],
        },
    )
    assert task.status_code == 201, task.text
    assert task.json()["labels"] == ["工作"]


def test_classification_name_is_bounded_and_duplicate_requests_are_rejected(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client, seed_classification=False)

    too_long = client.post(
        "/api/v1/workspaces/current/classifications",
        headers=_headers(owner),
        json={"request_id": str(uuid4()), "name": "六个字符名称"},
    )
    assert too_long.status_code == 422

    pending = client.post(
        "/api/v1/workspaces/current/classifications",
        headers=_headers(owner),
        json={"request_id": str(uuid4()), "name": "婚礼"},
    )
    assert pending.status_code == 202, pending.text
    duplicate_pending = client.post(
        "/api/v1/workspaces/current/classifications",
        headers=_headers(owner),
        json={"request_id": str(uuid4()), "name": " 婚礼 "},
    )
    assert duplicate_pending.status_code == 409

    approval = pending.json()["approval_request"]
    approved = client.post(
        f"/api/v1/workspaces/{approval['workspace_id']}/approval-requests/{approval['id']}/approve",
        headers=_headers(partner),
        json={"request_id": str(uuid4())},
    )
    assert approved.status_code == 200, approved.text
    duplicate = client.post(
        "/api/v1/workspaces/current/classifications",
        headers=_headers(owner),
        json={"request_id": str(uuid4()), "name": "婚礼"},
    )
    assert duplicate.status_code == 409


def test_classification_rejects_casefold_expansion_before_creating_approval(db_engine) -> None:
    client = _client(db_engine)
    owner, _partner = _ready_workspace(client, seed_classification=False)

    response = client.post(
        "/api/v1/workspaces/current/classifications",
        headers=_headers(owner),
        json={"request_id": str(uuid4()), "name": "ẞẞẞẞẞ"},
    )

    assert response.status_code == 422, response.text
    assert response.json()["code"] == "invalid_request"


def test_task_rejects_missing_or_unapproved_classification(db_engine) -> None:
    client = _client(db_engine)
    owner, _partner = _ready_workspace(client, seed_classification=False)

    missing = client.post(
        "/api/v1/tasks",
        headers=_headers(owner),
        json={"request_id": str(uuid4()), "title": "没有分类", "quadrant": "Q1"},
    )
    assert missing.status_code == 422
    assert missing.json()["code"] == "invalid_request"

    unknown = client.post(
        "/api/v1/tasks",
        headers=_headers(owner),
        json={
            "request_id": str(uuid4()),
            "title": "未批准分类",
            "quadrant": "Q1",
            "labels": ["工作"],
        },
    )
    assert unknown.status_code == 422
    assert unknown.json()["code"] == "classification_not_found"


def test_task_rejects_more_than_one_classification(db_engine) -> None:
    client = _client(db_engine)
    owner, _partner = _ready_workspace(client)

    response = client.post(
        "/api/v1/tasks",
        headers=_headers(owner),
        json={
            "request_id": str(uuid4()),
            "title": "单分类约束",
            "quadrant": "Q1",
            "labels": ["工作", "婚礼"],
        },
    )

    assert response.status_code == 422, response.text
    assert response.json()["code"] == "invalid_request"
