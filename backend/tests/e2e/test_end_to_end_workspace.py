"""In-process HTTP acceptance flow for the account/workspace/device contract."""

from __future__ import annotations

import base64
import hashlib
import json
from uuid import uuid4

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from fastapi.testclient import TestClient

from app.auth.providers.fake import FakeSmsProvider
from app.main import create_app


def _client(db_engine) -> TestClient:
    app = create_app()
    app.state.engine = db_engine
    app.state.ready = True
    app.state.sms_provider = FakeSmsProvider()
    return TestClient(app)


def _keypair() -> tuple[ec.EllipticCurvePrivateKey, str]:
    private = ec.generate_private_key(ec.SECP256R1())
    public = private.public_key().public_bytes(
        serialization.Encoding.DER,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    return private, base64.b64encode(public).decode("ascii")


def _login(client: TestClient, phone: str, public_key: str) -> dict[str, object]:
    sent = client.post("/api/v1/auth/sms/send", json={"phone": phone})
    assert sent.status_code == 202, sent.text
    response = client.post(
        "/api/v1/auth/sms/verify",
        json={
            "phone": phone,
            "code": client.app.state.sms_provider.last_code_for(phone),
            "device": {"public_key_der": public_key, "label": phone},
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


def _headers(session: dict[str, object]) -> dict[str, str]:
    return {"Authorization": f"Bearer {session['access_token']}"}


def _sign(private: ec.EllipticCurvePrivateKey, encoded_payload: str) -> str:
    padding = "=" * (-len(encoded_payload) % 4)
    payload = base64.urlsafe_b64decode(encoded_payload + padding)
    signature = private.sign(payload, ec.ECDSA(hashes.SHA256()))
    return base64.b64encode(signature).decode("ascii")


def test_two_person_device_and_web_session_lifecycle(db_engine) -> None:
    mobile = _client(db_engine)
    private_a, public_a = _keypair()
    private_b, public_b = _keypair()
    owner = _login(mobile, "+8613800138000", public_a)

    binding = mobile.post(
        "/api/v1/workspaces/bind-partner",
        headers=_headers(owner),
        json={"phone": "15028180169", "request_id": str(uuid4())},
    )
    assert binding.status_code == 201, binding.text
    partner = _login(mobile, "+8615028180169", public_b)
    accepted = mobile.post(
        f"/api/v1/workspace-invites/{binding.json()['invite']['id']}/accept",
        headers=_headers(partner),
        json={"request_id": str(uuid4())},
    )
    assert accepted.status_code == 200, accepted.text
    assert accepted.json()["state"] == "READY"

    created = mobile.post(
        "/api/v1/tasks",
        headers=_headers(owner),
        json={"request_id": str(uuid4()), "title": "A creates a task"},
    )
    assert created.status_code == 201, created.text
    task_id = created.json()["id"]

    private_b2, public_b2 = _keypair()
    pending = _login(mobile, "+8615028180169", public_b2)
    pending_headers = _headers(pending)
    bootstrap = mobile.get("/api/v1/workspaces/bootstrap", headers=pending_headers)
    assert bootstrap.status_code == 200, bootstrap.text
    assert bootstrap.json()["device"] == {"status": "UNVERIFIED", "can_write": False}
    assert any(item["id"] == task_id for item in mobile.get("/api/v1/tasks", headers=pending_headers).json())
    denied = mobile.post(
        "/api/v1/tasks",
        headers=pending_headers,
        json={"request_id": str(uuid4()), "title": "read only"},
    )
    assert denied.status_code == 403
    assert denied.json()["code"] == "device_not_verified"

    authorization = mobile.post(
        "/api/v1/devices/authorization-requests",
        headers=pending_headers,
        json={"public_key": public_b2, "label": "second phone"},
    )
    assert authorization.status_code == 201, authorization.text
    request_id = authorization.json()["id"]
    begin = mobile.post(
        f"/api/v1/device-authorization-requests/{request_id}/begin-approval",
        headers=_headers(owner),
    )
    assert begin.status_code == 200, begin.text
    approval = mobile.post(
        f"/api/v1/device-authorization-requests/{request_id}/approve",
        headers=_headers(owner),
        json={"signature": _sign(private_a, begin.json()["signature_payload"])},
    )
    assert approval.status_code == 200, approval.text

    writable = mobile.post(
        "/api/v1/tasks",
        headers=pending_headers,
        json={"request_id": str(uuid4()), "title": "approved device task"},
    )
    assert writable.status_code == 201, writable.text

    browser = _client(db_engine)
    proof = f"browser-proof-{uuid4()}"
    challenge = browser.post(
        "/api/v1/web-login/challenges",
        json={
            "origin": "https://muyu.example",
            "browser_proof_hash": hashlib.sha256(proof.encode()).hexdigest(),
        },
    )
    assert challenge.status_code == 201, challenge.text
    qr = json.loads(challenge.json()["qr_payload"])
    scanned = mobile.post(
        f"/api/v1/web-login/challenges/{challenge.json()['challenge_id']}/scan",
        headers=_headers(owner),
        json={"scan_nonce": qr["scan_nonce"]},
    )
    assert scanned.status_code == 200, scanned.text
    approved = mobile.post(
        f"/api/v1/web-login/challenges/{challenge.json()['challenge_id']}/approve",
        headers=_headers(owner),
        json={
            "scan_nonce": qr["scan_nonce"],
            "signature": _sign(private_a, scanned.json()["signature_payload"]),
        },
    )
    assert approved.status_code == 200, approved.text
    exchanged = browser.post(
        f"/api/v1/web-login/challenges/{challenge.json()['challenge_id']}/exchange",
        json={"browser_proof": proof},
    )
    assert exchanged.status_code == 200, exchanged.text

    browser_snapshot = browser.get("/api/v1/workspaces/current/snapshot")
    assert browser_snapshot.status_code == 200, browser_snapshot.text
    assert any(item["id"] == task_id for item in browser_snapshot.json()["tasks"])
    browser_created = browser.post(
        "/api/v1/tasks",
        json={"request_id": str(uuid4()), "title": "web task"},
    )
    assert browser_created.status_code == 201, browser_created.text
    assert any(
        item["id"] == browser_created.json()["id"]
        for item in mobile.get("/api/v1/tasks", headers=_headers(owner)).json()
    )
    browser_sessions = browser.get("/api/v1/web-sessions")
    assert browser_sessions.status_code == 200, browser_sessions.text
    web_session_id = browser_sessions.json()[0]["id"]
    assert set(browser_sessions.json()[0]) == {"id", "status", "origin", "created_at", "expires_at"}

    revoked = mobile.post(
        f"/api/v1/web-sessions/{web_session_id}/revoke",
        headers=_headers(owner),
    )
    assert revoked.status_code == 204, revoked.text
    assert browser.get("/api/v1/tasks").status_code == 401

    # The approved second device remains a durable Android device after the
    # browser session is revoked.
    device_list = mobile.get("/api/v1/devices", headers=pending_headers)
    assert device_list.status_code == 200, device_list.text
    assert any(item["id"] == pending["device_id"] and item["status"] == "VERIFIED" for item in device_list.json())
