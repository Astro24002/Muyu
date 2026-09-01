from datetime import datetime, timezone
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.db.enums import MembershipStatus
from app.db.models import User, Workspace, WorkspaceCursor, WorkspaceMembership
from app.main import create_app
from app.tasks.service import TaskService

from .test_lightweight_routes import FakeSmsProvider


def _client(db_engine) -> TestClient:
    app = create_app()
    app.state.engine = db_engine
    app.state.ready = True
    app.state.sms_provider = FakeSmsProvider()
    return TestClient(app)


def _authenticated(client: TestClient) -> str:
    phone = "+8613800138123"
    assert client.post("/api/v1/auth/sms/send", json={"phone": phone}).status_code == 202
    code = client.app.state.sms_provider.last_code_for(phone)
    response = client.post(
        "/api/v1/auth/sms/verify",
        json={"phone": phone, "code": code, "device": {"public_key_der": "AQID", "label": "contract"}},
    )
    assert response.status_code == 201, response.text
    workspace = client.post(
        "/api/v1/workspaces",
        headers={"Authorization": f"Bearer {response.json()['access_token']}"},
        json={"name": "Contract"},
    )
    assert workspace.status_code == 201, workspace.text
    return response.json()["access_token"]


def test_create_contract_exposes_versions_and_cursor(db_engine) -> None:
    client = _client(db_engine)
    headers = {"Authorization": f"Bearer {_authenticated(client)}"}
    response = client.post(
        "/api/v1/tasks",
        headers=headers,
        json={"request_id": str(uuid4()), "title": "  Contract task  ", "quadrant": "Q1", "labels": ["工作"]},
    )

    assert response.status_code == 201, response.text
    body = response.json()
    assert body["title"] == "Contract task"
    assert body["status"] == "TODO"
    assert body["quadrant"] == "Q1"
    assert body["labels"] == ["工作"]
    assert body["current_handler_id"]
    assert "assignee_ids" not in body
    assert body["version"] == 1
    assert body["field_versions"]["title"] == 1
    assert body["cursor"] == 1

    updated = client.patch(
        f"/api/v1/tasks/{body['id']}",
        headers=headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"title": "Updated contract task"},
            "base_field_versions": {"title": body["field_versions"]["title"]},
        },
    )
    assert updated.status_code == 200, updated.text
    assert "assignee_ids" not in updated.json()

    detail = client.get(f"/api/v1/tasks/{body['id']}", headers=headers)
    assert detail.status_code == 200, detail.text
    assert "assignee_ids" not in detail.json()

    snapshot = client.get("/api/v1/workspaces/current/snapshot", headers=headers)
    assert snapshot.status_code == 200, snapshot.text
    assert all("assignee_ids" not in task for task in snapshot.json()["tasks"])

    changes = client.get(
        "/api/v1/workspaces/current/changes?after_cursor=0", headers=headers
    )
    assert changes.status_code == 200, changes.text
    assert all(
        "assignee_ids" not in change["resource"]
        for change in changes.json()["changes"]
        if change["resource_type"] == "task" and change["resource"] is not None
    )


def test_create_rejects_empty_or_whitespace_title(db_engine) -> None:
    client = _client(db_engine)
    headers = {"Authorization": f"Bearer {_authenticated(client)}"}
    response = client.post(
        "/api/v1/tasks",
        headers=headers,
        json={"request_id": str(uuid4()), "title": "   ", "quadrant": "Q1"},
    )

    assert response.status_code == 422, response.text
    assert response.json()["code"] == "invalid_request"


@pytest.mark.parametrize("payload", [{"title": "Missing quadrant"}, {"title": "Null quadrant", "quadrant": None}])
def test_create_requires_quadrant_over_http(db_engine, payload: dict[str, object]) -> None:
    client = _client(db_engine)
    headers = {"Authorization": f"Bearer {_authenticated(client)}"}
    response = client.post(
        "/api/v1/tasks",
        headers=headers,
        json={"request_id": str(uuid4()), **payload},
    )

    assert response.status_code == 422, response.text
    assert response.json()["code"] == "invalid_request"
    assert client.get("/api/v1/tasks", headers=headers).json() == []


def test_create_normalizes_multiple_labels_over_http(db_engine) -> None:
    client = _client(db_engine)
    headers = {"Authorization": f"Bearer {_authenticated(client)}"}
    response = client.post(
        "/api/v1/tasks",
        headers=headers,
        json={
            "request_id": str(uuid4()),
            "title": "Label contract",
            "quadrant": "Q2",
            "labels": [" 工作 ", "婚礼", "婚礼", "党员"],
        },
    )

    assert response.status_code == 201, response.text
    assert response.json()["quadrant"] == "Q2"
    assert response.json()["labels"] == ["工作", "婚礼", "党员"]


@pytest.mark.parametrize(
    ("case", "labels"),
    [
        ("empty label", [""]),
        ("too many labels", [f"label-{index}" for index in range(11)]),
        ("label too long", ["a" * 33]),
    ],
)
def test_create_rejects_invalid_labels_before_commit_over_http(db_engine, case: str, labels: list[str]) -> None:
    client = _client(db_engine)
    headers = {"Authorization": f"Bearer {_authenticated(client)}"}
    response = client.post(
        "/api/v1/tasks",
        headers=headers,
        json={
            "request_id": str(uuid4()),
            "title": f"Invalid {case}",
            "quadrant": "Q4",
            "labels": labels,
        },
    )

    assert response.status_code == 422, response.text
    assert response.json()["code"] == "invalid_request"
    assert client.get("/api/v1/tasks", headers=headers).json() == []


def test_get_task_is_scoped_to_authenticated_workspace(db_engine) -> None:
    client = _client(db_engine)
    token = _authenticated(client)
    with Session(db_engine) as session:
        user = User(phone="+8613800138999")
        workspace = Workspace(name="Other")
        session.add_all([user, workspace])
        session.flush()
        session.add(
            WorkspaceMembership(
                workspace_id=workspace.id,
                user_id=user.id,
                member_slot=1,
                status=MembershipStatus.ACTIVE,
                joined_at=datetime.now(timezone.utc),
            )
        )
        session.add(WorkspaceCursor(workspace_id=workspace.id, next_cursor=1))
        session.flush()
        task = TaskService(session).create(workspace.id, user.id, uuid4(), "Private task", quadrant="Q1")
        session.commit()
        task_id = task.id

    response = client.get(f"/api/v1/tasks/{task_id}", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 404, response.text
    assert response.json()["code"] == "not_found"
