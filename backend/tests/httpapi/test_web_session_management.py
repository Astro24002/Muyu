from __future__ import annotations

import hashlib
from datetime import datetime, timedelta, timezone
from uuid import UUID, uuid4

from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth.providers.fake import FakeSmsProvider
from app.db.enums import DeviceStatus, WebSessionStatus
from app.db.models import AndroidDevice, MobileSession, WebSession, WorkspaceMembership
from app.main import create_app
from app.web_login.service import _digest


def _client(db_engine) -> TestClient:
    app = create_app()
    app.state.engine = db_engine
    app.state.ready = True
    app.state.sms_provider = FakeSmsProvider()
    return TestClient(app)


def _login(client: TestClient, phone: str, key: str) -> dict[str, object]:
    assert client.post("/api/v1/auth/sms/send", json={"phone": phone}).status_code == 202
    code = client.app.state.sms_provider.last_code_for(phone)
    response = client.post(
        "/api/v1/auth/sms/verify",
        json={"phone": phone, "code": code, "device": {"public_key_der": key}},
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


def _session(session: Session, user_id: UUID, workspace_id: UUID, device_id: UUID, digest: str, *, status: WebSessionStatus = WebSessionStatus.ACTIVE) -> WebSession:
    row = WebSession(
        user_id=user_id,
        workspace_id=workspace_id,
        approving_device_id=device_id,
        session_digest=digest,
        status=status,
        origin="https://muyu.example",
        expires_at=datetime.now(timezone.utc) + timedelta(hours=1),
    )
    session.add(row)
    session.flush()
    return row


def _legacy_pending_session(db_engine, source: dict[str, object]) -> dict[str, object]:
    token = f"legacy-{uuid4()}"
    now = datetime.now(timezone.utc)
    key = b"legacy-pending-web-session"
    with Session(db_engine) as session:
        device = AndroidDevice(
            user_id=UUID(str(source["user"]["id"])),
            public_key_der=key,
            fingerprint=hashlib.sha256(key).hexdigest(),
            status=DeviceStatus.PENDING,
        )
        session.add(device)
        session.flush()
        session.add(
            MobileSession(
                user_id=device.user_id,
                device_id=device.id,
                refresh_token_digest=hashlib.sha256(token.encode()).hexdigest(),
                expires_at=now + timedelta(hours=1),
            )
        )
        session.commit()
        return {"access_token": token}


def test_active_android_lists_and_revokes_workspace_web_sessions(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    with Session(db_engine) as session:
        workspace_id = session.scalar(select(WorkspaceMembership.workspace_id).where(WorkspaceMembership.user_id == UUID(str(owner["user"]["id"]))))
        assert workspace_id is not None
        first = _session(session, UUID(str(owner["user"]["id"])), workspace_id, UUID(str(owner["device_id"])), "web-one")
        second = _session(session, UUID(str(partner["user"]["id"])), workspace_id, UUID(str(partner["device_id"])), "web-two")
        first_id = str(first.id)
        second_id = str(second.id)
        session.commit()

    listed = client.get("/api/v1/web-sessions", headers=_headers(owner))
    assert listed.status_code == 200, listed.text
    body = listed.json()
    assert {item["id"] for item in body} == {first_id, second_id}
    assert all(set(item) == {"id", "status", "origin", "created_at", "expires_at"} for item in body)
    assert all("digest" not in item and "token" not in item for item in body)

    revoked = client.post(f"/api/v1/web-sessions/{second_id}/revoke", headers=_headers(owner))
    assert revoked.status_code == 204, revoked.text
    remaining = client.get("/api/v1/web-sessions", headers=_headers(owner))
    assert remaining.status_code == 200
    assert [item["id"] for item in remaining.json()] == [first_id]

    all_revoked = client.post("/api/v1/web-sessions/revoke-all", headers=_headers(owner))
    assert all_revoked.status_code == 200, all_revoked.text
    assert all_revoked.json() == {"revoked_count": 1}


def test_pending_android_and_web_session_cannot_revoke(db_engine) -> None:
    client = _client(db_engine)
    owner, _partner = _ready_workspace(client)
    pending = _legacy_pending_session(db_engine, owner)
    with Session(db_engine) as session:
        workspace_id = session.scalar(select(WorkspaceMembership.workspace_id).where(WorkspaceMembership.user_id == UUID(str(owner["user"]["id"]))))
        assert workspace_id is not None
        row = _session(session, UUID(str(owner["user"]["id"])), workspace_id, UUID(str(owner["device_id"])), "web-pending")
        row_id = str(row.id)
        session.commit()

    denied = client.post(f"/api/v1/web-sessions/{row_id}/revoke", headers=_headers(pending))
    assert denied.status_code == 403, denied.text
    assert denied.json()["code"] == "device_not_verified"

    web_denied = client.post(f"/api/v1/web-sessions/{row_id}/revoke")
    assert web_denied.status_code == 401, web_denied.text


def test_revoke_does_not_change_android_device(db_engine) -> None:
    client = _client(db_engine)
    owner, _partner = _ready_workspace(client)
    with Session(db_engine) as session:
        device_id = UUID(str(owner["device_id"]))
        device = session.get(AndroidDevice, device_id)
        assert device is not None
        workspace_id = session.scalar(select(WorkspaceMembership.workspace_id).where(WorkspaceMembership.user_id == device.user_id))
        row = _session(session, device.user_id, workspace_id, device.id, "web-device-state")
        row_id = str(row.id)
        session.commit()

    response = client.post(f"/api/v1/web-sessions/{row_id}/revoke", headers=_headers(owner))
    assert response.status_code == 204
    with Session(db_engine) as session:
        device = session.get(AndroidDevice, UUID(str(owner["device_id"])))
        assert device is not None and device.status == DeviceStatus.ACTIVE
        stored = session.get(WebSession, row_id)
        assert stored is not None and stored.status == WebSessionStatus.REVOKED


def test_browser_lists_and_revokes_only_its_own_web_session(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    raw_cookie = "browser-session-cookie"
    with Session(db_engine) as session:
        workspace_id = session.scalar(
            select(WorkspaceMembership.workspace_id).where(
                WorkspaceMembership.user_id == UUID(str(owner["user"]["id"])),
            )
        )
        assert workspace_id is not None
        own = _session(
            session,
            UUID(str(owner["user"]["id"])),
            workspace_id,
            UUID(str(owner["device_id"])),
            _digest(raw_cookie),
        )
        other = _session(
            session,
            UUID(str(partner["user"]["id"])),
            workspace_id,
            UUID(str(partner["device_id"])),
            "browser-other-session",
        )
        own_id = str(own.id)
        other_id = str(other.id)
        session.commit()

    client.cookies.set("muyu_web_session", raw_cookie)
    listed = client.get("/api/v1/web-sessions")
    assert listed.status_code == 200, listed.text
    assert [item["id"] for item in listed.json()] == [own_id]

    denied = client.post(f"/api/v1/web-sessions/{other_id}/revoke")
    assert denied.status_code == 403, denied.text
    revoked = client.post(f"/api/v1/web-sessions/{own_id}/revoke")
    assert revoked.status_code == 204, revoked.text
