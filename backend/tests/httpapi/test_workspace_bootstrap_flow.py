from __future__ import annotations

from uuid import UUID, uuid4

from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth.providers.fake import FakeSmsProvider
from app.db.enums import ApprovalStatus, DeviceStatus, InviteStatus, MembershipStatus
from app.db.models import AndroidDevice, DeviceAuthorizationRequest, User, WorkspaceInvite, WorkspaceMembership
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
    verified = client.post(
        "/api/v1/auth/sms/verify",
        json={
            "phone": phone,
            "code": code,
            "device": {"public_key_der": public_key_der, "label": public_key_der},
        },
    )
    assert verified.status_code == 201, verified.text
    return verified.json()


def _headers(session: dict[str, object]) -> dict[str, str]:
    return {"Authorization": f"Bearer {session['access_token']}"}


def test_first_login_requires_partner_phone(db_engine) -> None:
    client = _client(db_engine)
    first = _login(client, "+8613800138000", "AQID")

    response = client.get("/api/v1/workspaces/bootstrap", headers=_headers(first))

    assert response.status_code == 200, response.text
    assert response.json()["state"] == "NEEDS_PARTNER"
    assert response.json()["workspace"] is None
    assert response.json()["device"] == {"status": "VERIFIED", "can_write": True}


def test_bind_partner_creates_one_owner_and_pending_invite(db_engine) -> None:
    client = _client(db_engine)
    first = _login(client, "+8613800138000", "AQID")
    request_id = str(uuid4())

    response = client.post(
        "/api/v1/workspaces/bind-partner",
        headers=_headers(first),
        json={"phone": "15028180169", "request_id": request_id},
    )

    assert response.status_code == 201, response.text
    body = response.json()
    assert body["state"] == "WAITING_FOR_PARTNER"
    assert body["workspace"]["member_count"] == 1
    assert body["workspace"]["match_status"] == "waiting_partner"
    assert len(body["workspace"]["members"]) == 1
    assert body["workspace"]["members"][0]["member_slot"] == 1
    assert body["workspace"]["members"][0]["is_current"] is True
    assert body["invite"]["status"] == "PENDING"
    assert body["invite"]["phone_masked"] == "+86******0169"

    replay = client.post(
        "/api/v1/workspaces/bind-partner",
        headers=_headers(first),
        json={"phone": "15028180169", "request_id": request_id},
    )
    assert replay.status_code == 201, replay.text
    assert replay.json() == body

    with Session(db_engine) as session:
        owner = session.scalar(select(User).where(User.phone == "+8613800138000"))
        assert owner is not None
        memberships = session.scalars(
            select(WorkspaceMembership).where(WorkspaceMembership.user_id == owner.id)
        ).all()
        assert len(memberships) == 1
        assert memberships[0].member_slot == 1
        assert memberships[0].status == MembershipStatus.ACTIVE

        invites = session.scalars(select(WorkspaceInvite)).all()
        assert len(invites) == 1
        assert invites[0].invited_phone == "+8615028180169"
        assert invites[0].status == InviteStatus.PENDING


def test_partner_first_device_accepts_invite_without_device_approval(db_engine) -> None:
    client = _client(db_engine)
    owner = _login(client, "+8613800138000", "AQID")
    binding = client.post(
        "/api/v1/workspaces/bind-partner",
        headers=_headers(owner),
        json={"phone": "15028180169", "request_id": str(uuid4())},
    )
    assert binding.status_code == 201, binding.text
    invite_id = binding.json()["invite"]["id"]

    partner = _login(client, "+8615028180169", "BAUG")
    bootstrap = client.get("/api/v1/workspaces/bootstrap", headers=_headers(partner))
    assert bootstrap.status_code == 200, bootstrap.text
    assert bootstrap.json()["state"] == "INVITED"

    response = client.post(
        f"/api/v1/workspace-invites/{invite_id}/accept",
        headers=_headers(partner),
        json={"device_id": str(partner["device_id"]), "request_id": str(uuid4())},
    )

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["state"] == "READY"
    assert body["workspace"]["member_count"] == 2
    assert body["workspace"]["match_status"] == "matched"
    assert [item["member_slot"] for item in body["workspace"]["members"]] == [1, 2]
    assert body["workspace"]["members"][0]["is_current"] is False
    assert body["workspace"]["members"][1]["is_current"] is True
    assert body["workspace"]["members"][1]["phone_masked"].endswith("0169")
    assert body["device"] == {"status": "VERIFIED", "can_write": True}

    with Session(db_engine) as session:
        workspace_id = UUID(binding.json()["workspace"]["id"])
        members = session.scalars(
            select(WorkspaceMembership)
            .where(WorkspaceMembership.workspace_id == workspace_id)
            .order_by(WorkspaceMembership.member_slot)
        ).all()
        assert [(member.member_slot, member.status) for member in members] == [
            (1, MembershipStatus.ACTIVE),
            (2, MembershipStatus.ACTIVE),
        ]
        assert session.scalars(select(DeviceAuthorizationRequest)).all() == []


def test_second_device_can_accept_membership_without_device_approval(db_engine) -> None:
    client = _client(db_engine)
    owner = _login(client, "+8613800138000", "AQID")
    binding = client.post(
        "/api/v1/workspaces/bind-partner",
        headers=_headers(owner),
        json={"phone": "15028180169", "request_id": str(uuid4())},
    )
    assert binding.status_code == 201, binding.text
    invite_id = binding.json()["invite"]["id"]

    partner_first = _login(client, "+8615028180169", "BAUG")
    partner_second = _login(client, "+8615028180169", "BwgJ")
    assert partner_first["device_id"] != partner_second["device_id"]

    response = client.post(
        f"/api/v1/workspace-invites/{invite_id}/accept",
        headers=_headers(partner_second),
        json={"device_id": str(partner_second["device_id"]), "request_id": str(uuid4())},
    )

    assert response.status_code == 200, response.text
    assert response.json()["state"] == "READY"
    assert response.json()["device"] == {"status": "VERIFIED", "can_write": True}
    with Session(db_engine) as session:
        assert session.scalars(select(DeviceAuthorizationRequest)).all() == []
        membership = session.scalar(
            select(WorkspaceMembership).where(
                WorkspaceMembership.user_id == UUID(str(partner_first["user"]["id"])),
                WorkspaceMembership.member_slot == 2,
            )
        )
        assert membership is not None
        assert membership.status == MembershipStatus.ACTIVE
        device = session.get(AndroidDevice, UUID(str(partner_second["device_id"])))
        assert device is not None
        assert device.status == DeviceStatus.ACTIVE


def test_self_phone_and_second_workspace_are_rejected(db_engine) -> None:
    client = _client(db_engine)
    first = _login(client, "+8613800138000", "AQID")

    response = client.post(
        "/api/v1/workspaces/bind-partner",
        headers=_headers(first),
        json={"phone": "13800138000", "request_id": str(uuid4())},
    )

    assert response.status_code == 422, response.text
    assert response.json()["code"] == "partner_phone_must_differ"


def test_bind_partner_request_id_rejects_a_different_phone(db_engine) -> None:
    client = _client(db_engine)
    first = _login(client, "+8613800138000", "AQID")
    request_id = str(uuid4())

    created = client.post(
        "/api/v1/workspaces/bind-partner",
        headers=_headers(first),
        json={"phone": "15028180169", "request_id": request_id},
    )
    assert created.status_code == 201, created.text

    mismatch = client.post(
        "/api/v1/workspaces/bind-partner",
        headers=_headers(first),
        json={"phone": "15028180170", "request_id": request_id},
    )
    assert mismatch.status_code == 409, mismatch.text
    assert mismatch.json()["code"] == "idempotency_key_reused"
