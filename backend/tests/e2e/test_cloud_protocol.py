"""Opt-in end-to-end contract for the cloud identity and sync protocol.

The test is deliberately opt-in because it talks to a disposable PostgreSQL
stack and a fake SMS provider, rather than the unit-test application fixture.
"""

from __future__ import annotations

import os
from uuid import uuid4

import httpx
import pytest
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat


def _request_id() -> str:
    return str(uuid4())


@pytest.mark.cloud_protocol
def test_cloud_protocol_registration_invitation_sync_and_web_approval() -> None:
    """Exercise the cross-client protocol against a running cloud stack."""
    if os.getenv("RUN_CLOUD_PROTOCOL") != "1":
        pytest.skip("set RUN_CLOUD_PROTOCOL=1 for the disposable cloud protocol stack")

    base_url = os.getenv("CLOUD_PROTOCOL_BASE_URL", "http://localhost:8080")
    code_a = os.getenv("OTP_CODE_A", "000000")
    code_b = os.getenv("OTP_CODE_B", "000000")
    phone_a = "+15550000001"
    phone_b = "+15550000002"
    private_key = ec.generate_private_key(ec.SECP256R1())
    public_key = private_key.public_key().public_bytes(Encoding.DER, PublicFormat.SubjectPublicKeyInfo)

    with httpx.Client(base_url=base_url, timeout=15.0) as client:
        assert client.get("/health/ready").status_code == 200
        for phone, code in ((phone_a, code_a), (phone_b, code_b)):
            sent = client.post(
                "/api/v1/auth/sms/send",
                json={"phone": phone, "request_id": _request_id()},
            )
            assert sent.status_code == 202
            verified = client.post(
                "/api/v1/auth/sms/verify",
                json={
                    "phone": phone,
                    "code": code,
                    "public_key": public_key.hex(),
                    "request_id": _request_id(),
                },
            )
            assert verified.status_code == 201
            if phone == phone_a:
                access_a = verified.json()["access_token"]
            else:
                access_b = verified.json()["access_token"]

        headers_a = {"Authorization": f"Bearer {access_a}"}
        headers_b = {"Authorization": f"Bearer {access_b}"}
        workspace = client.post(
            "/api/v1/workspaces",
            headers=headers_a,
            json={"name": "protocol test", "request_id": _request_id()},
        )
        assert workspace.status_code == 201
        workspace_id = workspace.json()["id"]
        invite = client.post(
            f"/api/v1/workspaces/{workspace_id}/invites",
            headers=headers_a,
            json={"phone": phone_b, "request_id": _request_id()},
        )
        assert invite.status_code == 201

        task = client.post(
            "/api/v1/tasks",
            headers=headers_a,
            json={"title": "protocol task", "request_id": _request_id()},
        )
        assert task.status_code == 201
        task_id = task.json()["id"]
        assert client.get("/api/v1/tasks", headers=headers_b).status_code == 200

        change = client.patch(
            f"/api/v1/tasks/{task_id}",
            headers=headers_b,
            json={"title": "partner edit", "request_id": _request_id()},
        )
        assert change.status_code in {200, 409}
        snapshot = client.get("/api/v1/workspaces/current/snapshot", headers=headers_b)
        assert snapshot.status_code == 200
        stale = client.get(
            "/api/v1/workspaces/current/changes?after_cursor=0",
            headers=headers_b,
        )
        assert stale.status_code in {200, 410}

        challenge = client.post(
            "/api/v1/web-login/challenges",
            json={"browser_proof_hash": "test-proof", "origin": "https://muyu.example"},
        )
        assert challenge.status_code == 201
        assert "qr_payload" in challenge.json()
