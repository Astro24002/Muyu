"""Opt-in HTTP contract for the cloud identity, workspace, and Web flows."""

from __future__ import annotations

import base64
import hashlib
import json
import os
from datetime import datetime
from uuid import UUID, uuid4

import httpx
import pytest
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec

from app.devices.signatures import signed_action_payload


def _request_id() -> str:
    return str(uuid4())


def _keypair() -> tuple[ec.EllipticCurvePrivateKey, str]:
    private = ec.generate_private_key(ec.SECP256R1())
    public = private.public_key().public_bytes(
        serialization.Encoding.DER,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    return private, base64.b64encode(public).decode("ascii")


@pytest.mark.cloud_protocol
def test_cloud_protocol_registration_invitation_sync_and_web_approval() -> None:
    if os.getenv("RUN_CLOUD_PROTOCOL") != "1":
        pytest.skip("set RUN_CLOUD_PROTOCOL=1 for the disposable cloud protocol stack")

    base_url = os.getenv("CLOUD_PROTOCOL_BASE_URL", "http://localhost:8080")
    code = os.getenv("FAKE_OTP_CODE", "000000")
    phone_a = "+14155552671"
    phone_b = "+14155552672"
    private_a, public_a = _keypair()
    _private_b, public_b = _keypair()

    with httpx.Client(base_url=base_url, timeout=15.0) as client:
        assert client.get("/health/ready").status_code == 200

        def verify(phone: str, public_key: str) -> dict[str, object]:
            assert client.post("/api/v1/auth/sms/send", json={"phone": phone}).status_code == 202
            response = client.post(
                "/api/v1/auth/sms/verify",
                json={
                    "phone": phone,
                    "code": code,
                    "device": {"public_key_der": public_key, "label": "protocol"},
                },
            )
            assert response.status_code == 201, response.text
            return response.json()

        session_a = verify(phone_a, public_a)
        session_b = verify(phone_b, public_b)
        headers_a = {"Authorization": f"Bearer {session_a['access_token']}"}
        headers_b = {"Authorization": f"Bearer {session_b['access_token']}"}
        device_b = UUID(str(session_b["device_id"]))

        workspace_response = client.post(
            "/api/v1/workspaces",
            headers=headers_a,
            json={"name": "protocol test"},
        )
        assert workspace_response.status_code == 201, workspace_response.text
        workspace = workspace_response.json()
        workspace_id = UUID(workspace["id"])

        invite_response = client.post(
            f"/api/v1/workspaces/{workspace_id}/invites",
            headers=headers_a,
            json={"phone": phone_b},
        )
        assert invite_response.status_code == 201, invite_response.text
        invite_id = invite_response.json()["id"]

        accepted = client.post(
            f"/api/v1/workspace-invites/{invite_id}/accept",
            headers=headers_b,
            json={"device_id": str(device_b)},
        )
        assert accepted.status_code == 202, accepted.text
        request_id = accepted.json()["authorization_request_id"]

        challenge_response = client.post(
            f"/api/v1/device-authorization-requests/{request_id}/begin-approval",
            headers=headers_a,
        )
        assert challenge_response.status_code == 200, challenge_response.text
        challenge = challenge_response.json()
        expires_at = datetime.fromisoformat(challenge["expires_at"])
        payload = signed_action_payload(
            action="DEVICE_APPROVE",
            approval_id=UUID(request_id),
            actor_device_id=UUID(str(session_a["device_id"])),
            workspace_id=workspace_id,
            nonce=base64.urlsafe_b64decode(challenge["nonce"] + "=" * (-len(challenge["nonce"]) % 4)),
            expires_at=expires_at,
        )
        signature = private_a.sign(payload, ec.ECDSA(hashes.SHA256()))
        approved = client.post(
            f"/api/v1/device-authorization-requests/{request_id}/approve",
            headers=headers_a,
            json={"signature": base64.b64encode(signature).decode("ascii")},
        )
        assert approved.status_code == 200, approved.text

        task = client.post(
            "/api/v1/tasks",
            headers=headers_a,
            json={"title": "protocol task", "description": "", "request_id": _request_id()},
        )
        assert task.status_code == 201, task.text
        task_id = task.json()["id"]
        assert client.get("/api/v1/tasks", headers=headers_b).status_code == 200

        snapshot = client.get("/api/v1/workspaces/current/snapshot", headers=headers_b)
        assert snapshot.status_code == 200, snapshot.text
        assert any(item["id"] == task_id for item in snapshot.json()["tasks"])
        changes = client.get("/api/v1/workspaces/current/changes?after_cursor=0", headers=headers_b)
        assert changes.status_code == 200, changes.text

        proof = "browser-proof-" + _request_id()
        challenge_response = client.post(
            "/api/v1/web-login/challenges",
            json={
                "browser_proof_hash": hashlib.sha256(proof.encode()).hexdigest(),
                "origin": "https://muyu.example",
            },
        )
        assert challenge_response.status_code == 201, challenge_response.text
        assert "qr_payload" in challenge_response.json()
