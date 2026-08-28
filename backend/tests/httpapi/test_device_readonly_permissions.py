from __future__ import annotations

from uuid import UUID, uuid4

from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth.providers.fake import FakeSmsProvider
from app.db.enums import DeviceStatus
from app.db.models import AndroidDevice
from app.main import create_app


def _client(db_engine) -> TestClient:
    app = create_app()
    app.state.engine = db_engine
    app.state.ready = True
    app.state.sms_provider = FakeSmsProvider()
    return TestClient(app)


def _login(client: TestClient, phone: str, public_key_der: str) -> dict[str, object]:
    sent = client.post("/api/v1/auth/sms/send", json={"phone": phone})
    assert sent.status_code == 202, sent.text
    code = client.app.state.sms_provider.last_code_for(phone)
    response = client.post(
        "/api/v1/auth/sms/verify",
        json={
            "phone": phone,
            "code": code,
            "device": {"public_key_der": public_key_der, "label": public_key_der},
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


def _headers(session: dict[str, object]) -> dict[str, str]:
    return {"Authorization": f"Bearer {session['access_token']}"}


def _ready_workspace(client: TestClient) -> tuple[dict[str, object], dict[str, object]]:
    owner = _login(client, "+8613800138000", "AQID")
    bound = client.post(
        "/api/v1/workspaces/bind-partner",
        headers=_headers(owner),
        json={"phone": "+8615028180169", "request_id": str(uuid4())},
    )
    assert bound.status_code == 201, bound.text
    partner = _login(client, "+8615028180169", "BAUG")
    accepted = client.post(
        f"/api/v1/workspace-invites/{bound.json()['invite']['id']}/accept",
        headers=_headers(partner),
        json={"device_id": partner["device_id"], "request_id": str(uuid4())},
    )
    assert accepted.status_code == 200, accepted.text
    return owner, partner


def test_pending_device_can_refresh_and_read_workspace(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    pending = _login(client, "+8615028180169", "BwgJ")

    refreshed = client.post(
        "/api/v1/auth/mobile/refresh",
        json={"refresh_token": pending["refresh_token"]},
    )
    assert refreshed.status_code == 200, refreshed.text

    headers = _headers(refreshed.json())
    bootstrap = client.get("/api/v1/workspaces/bootstrap", headers=headers)
    assert bootstrap.status_code == 200, bootstrap.text
    assert bootstrap.json()["state"] == "READY"
    assert bootstrap.json()["device"] == {"status": "UNVERIFIED", "can_write": False}

    snapshot = client.get("/api/v1/workspaces/current/snapshot", headers=headers)
    assert snapshot.status_code == 200, snapshot.text
    tasks = client.get("/api/v1/tasks", headers=headers)
    assert tasks.status_code == 200, tasks.text


def test_pending_device_is_rejected_by_every_task_write_with_device_not_verified(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    created = client.post(
        "/api/v1/tasks",
        headers=_headers(owner),
        json={"request_id": str(uuid4()), "title": "Read-only task"},
    )
    assert created.status_code == 201, created.text
    task = created.json()
    pending = _login(client, "+8615028180169", "BwgJ")
    headers = _headers(pending)

    cases = [
        (
            "post",
            "/api/v1/tasks",
            {"request_id": str(uuid4()), "title": "Denied"},
        ),
        (
            "patch",
            f"/api/v1/tasks/{task['id']}",
            {
                "request_id": str(uuid4()),
                "changes": {"title": "Denied"},
                "base_field_versions": {"title": task["field_versions"]["title"]},
            },
        ),
        (
            "post",
            f"/api/v1/tasks/{task['id']}/transition",
            {
                "request_id": str(uuid4()),
                "target_status": "IN_PROGRESS",
                "base_status_version": task["status_version"],
            },
        ),
        (
            "post",
            f"/api/v1/tasks/{task['id']}/comments",
            {"request_id": str(uuid4()), "body": "Denied"},
        ),
        (
            "post",
            f"/api/v1/tasks/{task['id']}/delays",
            {
                "request_id": str(uuid4()),
                "new_due_at": "2030-01-01T00:00:00+00:00",
                "reason": "OTHER",
            },
        ),
    ]
    for method, path, body in cases:
        response = getattr(client, method)(path, headers=headers, json=body)
        assert response.status_code == 403, (method, path, response.text)
        assert response.json()["code"] == "device_not_verified"


def test_active_device_can_write_and_revoked_device_cannot_refresh(db_engine) -> None:
    client = _client(db_engine)
    owner, _partner = _ready_workspace(client)
    created = client.post(
        "/api/v1/tasks",
        headers=_headers(owner),
        json={"request_id": str(uuid4()), "title": "Writable task"},
    )
    assert created.status_code == 201, created.text

    with Session(db_engine) as session:
        device_id = UUID(str(owner["device_id"]))
        device = session.get(AndroidDevice, device_id)
        assert device is not None
        device.status = DeviceStatus.REVOKED
        session.commit()

    refreshed = client.post(
        "/api/v1/auth/mobile/refresh",
        json={"refresh_token": owner["refresh_token"]},
    )
    assert refreshed.status_code == 403
    assert refreshed.json()["code"] == "device_not_active"
