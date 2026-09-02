from __future__ import annotations

import base64
import hashlib
from datetime import datetime, timedelta, timezone
from uuid import UUID, uuid4

from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth.providers.fake import FakeSmsProvider
from app.db.enums import ApprovalStatus, DeviceStatus, MembershipStatus, WebSessionStatus
from app.db.models import (
    AndroidDevice,
    DeviceAuthorizationRequest,
    MobileSession,
    WebSession,
    WorkspaceMembership,
)
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
    provider = client.app.state.sms_provider
    code = provider.last_code_for(phone)
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


def _legacy_pending_session(
    db_engine, source: dict[str, object], public_key_der: str
) -> dict[str, object]:
    token = f"legacy-{uuid4()}"
    now = datetime.now(timezone.utc)
    key = base64.b64decode(public_key_der)
    with Session(db_engine) as session:
        device = AndroidDevice(
            user_id=UUID(str(source["user"]["id"])),
            public_key_der=key,
            fingerprint=hashlib.sha256(key).hexdigest(),
            label="Legacy pending",
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
        return {
            "access_token": token,
            "refresh_token": token,
            "device_id": str(device.id),
            "user": source["user"],
        }


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


def test_device_list_returns_only_android_devices(db_engine) -> None:
    client = _client(db_engine)
    _owner, partner = _ready_workspace(client)
    second = _login(client, "+8615028180169", "BwgJ")

    with Session(db_engine) as session:
        # A web session is a separate temporary credential and must never be
        # represented as an Android device in the public list.
        workspace_id = session.scalar(
            select(WorkspaceMembership.workspace_id).where(
                WorkspaceMembership.user_id == UUID(str(partner["user"]["id"])),
                WorkspaceMembership.status == MembershipStatus.ACTIVE,
            )
        )
        assert workspace_id is not None
        web_session = WebSession(
            user_id=UUID(str(partner["user"]["id"])),
            workspace_id=workspace_id,
            approving_device_id=UUID(str(partner["device_id"])),
            session_digest="web-device-list-test",
            status=WebSessionStatus.ACTIVE,
            expires_at=datetime.now(timezone.utc),
        )
        session.add(web_session)
        session.commit()
        web_session_id = str(web_session.id)

    response = client.get("/api/v1/devices", headers=_headers(second))
    assert response.status_code == 200, response.text
    devices = response.json()
    assert {item["platform"] for item in devices} == {"ANDROID"}
    assert {item["status"] for item in devices} == {"VERIFIED"}
    assert web_session_id not in {item["id"] for item in devices}
    assert any(item["is_current"] and item["status"] == "VERIFIED" for item in devices)
    assert {item["can_write"] for item in devices} == {True}


def test_authorization_request_is_idempotent_and_visible_to_both_members(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    pending = _legacy_pending_session(db_engine, owner, "BwgJ")

    first = client.post(
        "/api/v1/devices/authorization-requests",
        headers=_headers(pending),
        json={"public_key": "BwgJ", "label": "Pixel 9"},
    )
    second = client.post(
        "/api/v1/devices/authorization-requests",
        headers=_headers(pending),
        json={"public_key": "BwgJ", "label": "Pixel 9"},
    )

    assert first.status_code == 201, first.text
    assert second.status_code == 201, second.text
    assert first.json()["id"] == second.json()["id"]

    incoming = client.get(
        "/api/v1/devices/authorization-requests",
        headers=_headers(partner),
    )
    outgoing = client.get(
        "/api/v1/devices/authorization-requests",
        headers=_headers(pending),
    )
    assert incoming.status_code == 200, incoming.text
    assert outgoing.status_code == 200, outgoing.text
    assert incoming.json()[0]["is_incoming"] is True
    assert outgoing.json()[0]["is_incoming"] is False
    assert incoming.json()[0]["candidate_device_label"] == "Pixel 9"
    assert outgoing.json()[0]["candidate_user_id"] == pending["user"]["id"]

    with Session(db_engine) as session:
        assert len(session.scalars(select(DeviceAuthorizationRequest)).all()) == 1


def test_active_partner_can_reject_pending_device_request(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    pending = _legacy_pending_session(db_engine, owner, "Bwga")
    created = client.post(
        "/api/v1/devices/authorization-requests",
        headers=_headers(pending),
        json={"public_key": "Bwga", "label": "Reject me"},
    )
    assert created.status_code == 201, created.text

    request_id = created.json()["id"]
    rejected = client.post(
        f"/api/v1/devices/authorization-requests/{request_id}/reject",
        headers=_headers(partner),
    )

    assert rejected.status_code == 200, rejected.text
    assert rejected.json() == {"id": request_id, "status": "REJECTED"}
    with Session(db_engine) as session:
        request = session.get(DeviceAuthorizationRequest, UUID(request_id))
        assert request is not None
        device = session.get(AndroidDevice, request.candidate_device_id)
        assert device is not None and device.status == DeviceStatus.PENDING
        assert request.status == ApprovalStatus.REJECTED


def test_pending_device_only_sees_its_own_authorization_requests(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    owner_pending = _legacy_pending_session(db_engine, owner, "Bwgb")
    created = client.post(
        "/api/v1/devices/authorization-requests",
        headers=_headers(owner_pending),
        json={"public_key": "Bwgb", "label": "Owner pending"},
    )
    assert created.status_code == 201, created.text

    partner_pending = _legacy_pending_session(db_engine, partner, "Bwgc")
    response = client.get(
        "/api/v1/devices/authorization-requests",
        headers=_headers(partner_pending),
    )

    assert response.status_code == 200, response.text
    assert response.json() == []


def test_current_device_cannot_revoke_itself_even_with_another_active_device(db_engine) -> None:
    client = _client(db_engine)
    owner, _partner = _ready_workspace(client)
    second = _login(client, "+8613800138000", "AQIE")
    with Session(db_engine) as session:
        second_device = session.get(AndroidDevice, UUID(str(second["device_id"])))
        assert second_device is not None
        second_device.status = DeviceStatus.ACTIVE
        session.commit()

    response = client.post(
        f"/api/v1/devices/{owner['device_id']}/revoke",
        headers=_headers(owner),
    )
    assert response.status_code == 403, response.text
    assert response.json()["code"] == "approval_not_allowed"


def test_active_device_can_revoke_other_device_and_replay_is_conflict(db_engine) -> None:
    client = _client(db_engine)
    owner, _partner = _ready_workspace(client)
    other = _login(client, "+8613800138000", "AQIF")
    with Session(db_engine) as session:
        other_device = session.get(AndroidDevice, UUID(str(other["device_id"])))
        assert other_device is not None
        other_device.status = DeviceStatus.ACTIVE
        session.commit()

    response = client.post(
        f"/api/v1/devices/{other['device_id']}/revoke",
        headers=_headers(owner),
    )
    assert response.status_code == 200, response.text
    assert response.json()["id"] == other["device_id"]
    assert response.json()["status"] == "REVOKED"

    refreshed = client.post(
        "/api/v1/auth/mobile/refresh",
        json={"refresh_token": other["refresh_token"]},
    )
    assert refreshed.status_code == 403, refreshed.text
    assert refreshed.json()["code"] == "device_not_active"

    repeated = client.post(
        f"/api/v1/devices/{other['device_id']}/revoke",
        headers=_headers(owner),
    )
    assert repeated.status_code == 409, repeated.text
    assert repeated.json()["code"] == "device_already_revoked"


def test_revoke_invalidates_all_mobile_sessions_for_other_device(db_engine) -> None:
    client = _client(db_engine)
    owner, _partner = _ready_workspace(client)
    other = _login(client, "+8613800138000", "AQIG")
    _login(client, "+8613800138000", "AQIG")
    with Session(db_engine) as session:
        workspace_id = session.scalar(
            select(WorkspaceMembership.workspace_id).where(
                WorkspaceMembership.user_id == UUID(str(owner["user"]["id"])),
                WorkspaceMembership.status == MembershipStatus.ACTIVE,
            )
        )
        assert workspace_id is not None
        authorization = DeviceAuthorizationRequest(
            workspace_id=workspace_id,
            candidate_device_id=UUID(str(other["device_id"])),
            status=ApprovalStatus.PENDING,
            safety_code_digest="pending-revoke-digest",
            expires_at=datetime.now(timezone.utc) + timedelta(minutes=10),
        )
        session.add(authorization)
        session.commit()
        authorization_id = authorization.id

    response = client.post(
        f"/api/v1/devices/{other['device_id']}/revoke",
        headers=_headers(owner),
    )
    assert response.status_code == 200, response.text

    with Session(db_engine) as session:
        device = session.get(AndroidDevice, UUID(str(other["device_id"])))
        assert device is not None
        assert device.status == DeviceStatus.REVOKED
        mobile_sessions = session.scalars(
            select(MobileSession).where(MobileSession.device_id == device.id)
        ).all()
        assert len(mobile_sessions) == 2
        assert all(item.revoked_at is not None for item in mobile_sessions)
        request = session.get(DeviceAuthorizationRequest, authorization_id)
        assert request is not None
        assert request.status == ApprovalStatus.REVOKED
        assert request.revoked_at is not None


def test_pending_device_cannot_revoke_any_device(db_engine) -> None:
    client = _client(db_engine)
    owner, _partner = _ready_workspace(client)
    pending = _legacy_pending_session(db_engine, owner, "AQIH")

    response = client.post(
        f"/api/v1/devices/{owner['device_id']}/revoke",
        headers=_headers(pending),
    )

    assert response.status_code == 403, response.text
    assert response.json()["code"] == "device_not_verified"


def test_device_revoke_is_limited_to_the_same_account(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)

    response = client.post(
        f"/api/v1/devices/{partner['device_id']}/revoke",
        headers=_headers(owner),
    )

    assert response.status_code == 403, response.text
    assert response.json()["code"] == "approval_not_allowed"
