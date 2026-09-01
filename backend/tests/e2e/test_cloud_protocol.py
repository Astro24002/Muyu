"""Opt-in HTTP contract for the cloud identity, workspace, and Web flows."""

from __future__ import annotations

import base64
import hashlib
import json
import os
from datetime import datetime, timezone
from uuid import UUID, uuid4

import httpx
import pytest
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.devices.signatures import signed_action_payload
from app.auth.providers.fake import FakeSmsProvider
from app.db.enums import MembershipStatus
from app.db.models import User, WorkspaceMembership
from app.main import create_app


def _request_id() -> str:
    return str(uuid4())


def _keypair() -> tuple[ec.EllipticCurvePrivateKey, str]:
    private = ec.generate_private_key(ec.SECP256R1())
    public = private.public_key().public_bytes(
        serialization.Encoding.DER,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    return private, base64.b64encode(public).decode("ascii")


def _task_client(db_engine) -> TestClient:
    app = create_app()
    app.state.engine = db_engine
    app.state.ready = True
    app.state.sms_provider = FakeSmsProvider("000000")
    return TestClient(app)


def _task_user(client: TestClient, phone: str) -> dict[str, object]:
    sent = client.post("/api/v1/auth/sms/send", json={"phone": phone})
    assert sent.status_code == 202, sent.text
    verified = client.post(
        "/api/v1/auth/sms/verify",
        json={
            "phone": phone,
            "code": client.app.state.sms_provider.last_code_for(phone),
            "device": {"public_key_der": "AQID", "label": "task-acceptance"},
        },
    )
    assert verified.status_code == 201, verified.text
    return verified.json()


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
            json={"title": "protocol task", "description": "", "quadrant": "Q1", "request_id": _request_id()},
        )
        assert task.status_code == 201, task.text
        task_id = task.json()["id"]
        assert "assignee_ids" not in task.json()
        assert client.get("/api/v1/tasks", headers=headers_b).status_code == 200

        snapshot = client.get("/api/v1/workspaces/current/snapshot", headers=headers_b)
        assert snapshot.status_code == 200, snapshot.text
        assert any(item["id"] == task_id for item in snapshot.json()["tasks"])
        assert all("assignee_ids" not in item for item in snapshot.json()["tasks"])
        changes = client.get("/api/v1/workspaces/current/changes?after_cursor=0", headers=headers_b)
        assert changes.status_code == 200, changes.text
        assert all(
            "assignee_ids" not in item["resource"]
            for item in changes.json()["changes"]
            if item["resource_type"] == "task" and item["resource"] is not None
        )

        proof = "browser-proof-" + _request_id()
        challenge_response = client.post(
            "/api/v1/web-login/challenges",
            json={
                "browser_proof_hash": hashlib.sha256(proof.encode()).hexdigest(),
                "origin": "https://muyu.example",
            },
        )
        assert challenge_response.status_code == 201, challenge_response.text
        web_challenge = challenge_response.json()
        qr_payload = json.loads(web_challenge["qr_payload"])
        assert qr_payload["challenge_id"] == web_challenge["challenge_id"]

        scanned = client.post(
            f"/api/v1/web-login/challenges/{web_challenge['challenge_id']}/scan",
            headers=headers_a,
            json={"scan_nonce": qr_payload["scan_nonce"]},
        )
        assert scanned.status_code == 200, scanned.text
        signed_web_approval = signed_action_payload(
            action="WEB_LOGIN_APPROVE",
            approval_id=UUID(web_challenge["challenge_id"]),
            actor_device_id=UUID(str(session_a["device_id"])),
            workspace_id=workspace_id,
            nonce=qr_payload["scan_nonce"].encode("utf-8"),
            expires_at=datetime.fromisoformat(qr_payload["expires_at"]),
        )
        web_approval = client.post(
            f"/api/v1/web-login/challenges/{web_challenge['challenge_id']}/approve",
            headers=headers_a,
            json={
                "signature": base64.b64encode(
                    private_a.sign(signed_web_approval, ec.ECDSA(hashes.SHA256()))
                ).decode("ascii")
            },
        )
        assert web_approval.status_code == 200, web_approval.text

        exchanged = client.post(
            f"/api/v1/web-login/challenges/{web_challenge['challenge_id']}/exchange",
            json={"browser_proof": proof},
        )
        assert exchanged.status_code == 200, exchanged.text
        set_cookie = exchanged.headers["set-cookie"]
        assert "muyu_web_session=" in set_cookie
        assert "HttpOnly" in set_cookie
        assert "SameSite=lax" in set_cookie

        browser_snapshot = client.get("/api/v1/workspaces/current/snapshot")
        assert browser_snapshot.status_code == 200, browser_snapshot.text
        assert any(item["id"] == task_id for item in browser_snapshot.json()["tasks"])

        web_sessions = client.get("/api/v1/web-login/sessions")
        assert web_sessions.status_code == 200, web_sessions.text
        session_id = web_sessions.json()[0]["id"]
        revoked = client.post(f"/api/v1/web-login/sessions/{session_id}/revoke", headers=headers_a)
        assert revoked.status_code == 204, revoked.text
        assert client.get("/api/v1/tasks").status_code == 401


@pytest.mark.cloud_protocol
@pytest.mark.skipif(
    os.getenv("RUN_CLOUD_PROTOCOL") != "1",
    reason="set RUN_CLOUD_PROTOCOL=1 for the disposable cloud protocol stack",
)
def test_two_user_task_workflow_postgresql(db_engine) -> None:
    """Run the task workflow against PostgreSQL with two authenticated users."""

    phone_a = "+14155552671"
    phone_b = "+14155552672"
    client = _task_client(db_engine)
    session_a = _task_user(client, phone_a)
    session_b = _task_user(client, phone_b)
    headers_a = {"Authorization": f"Bearer {session_a['access_token']}"}
    headers_b = {"Authorization": f"Bearer {session_b['access_token']}"}

    workspace_response = client.post(
        "/api/v1/workspaces",
        headers=headers_a,
        json={"name": "Task acceptance"},
    )
    assert workspace_response.status_code == 201, workspace_response.text
    workspace_id = UUID(workspace_response.json()["id"])

    # Workspace onboarding is covered by the cloud protocol test above. Seed
    # the second active membership here so this test stays focused on task
    # synchronization and lifecycle behavior.
    with Session(db_engine) as session:
        user_b = session.scalar(select(User).where(User.phone == phone_b))
        assert user_b is not None
        session.add(
            WorkspaceMembership(
                workspace_id=workspace_id,
                user_id=user_b.id,
                member_slot=2,
                status=MembershipStatus.ACTIVE,
                joined_at=datetime.now(timezone.utc),
            )
        )
        session.commit()

    before_create = client.get("/api/v1/workspaces/current/snapshot", headers=headers_b)
    assert before_create.status_code == 200, before_create.text
    assert before_create.json()["cursor"] == 0
    user_a_id = UUID(str(session_a["user"]["id"]))
    user_b_id = UUID(str(session_b["user"]["id"]))

    due_at = "2026-09-01T12:00:00+00:00"
    created = client.post(
        "/api/v1/tasks",
        headers=headers_a,
        json={
            "request_id": str(uuid4()),
            "title": "Shared acceptance task",
            "description": "initial description",
            "quadrant": "Q2",
            "due_at": due_at,
        },
    )
    assert created.status_code == 201, created.text
    task = created.json()
    task_id = task["id"]
    assert task["cursor"] == 1
    assert task["current_handler_id"] == str(user_a_id)
    assert "assignee_ids" not in task

    b_snapshot = client.get("/api/v1/workspaces/current/snapshot", headers=headers_b)
    assert b_snapshot.status_code == 200, b_snapshot.text
    assert b_snapshot.json()["cursor"] == task["cursor"]
    assert b_snapshot.json()["tasks"][0]["id"] == task_id
    assert "assignee_ids" not in b_snapshot.json()["tasks"][0]
    b_changes = client.get("/api/v1/workspaces/current/changes?after_cursor=0", headers=headers_b)
    assert b_changes.status_code == 200, b_changes.text
    assert [item["cursor"] for item in b_changes.json()["changes"]] == [1]
    assert b_changes.json()["changes"][0]["resource"]["title"] == "Shared acceptance task"
    assert "assignee_ids" not in b_changes.json()["changes"][0]["resource"]

    current = client.patch(
        f"/api/v1/tasks/{task_id}",
        headers=headers_a,
        json={
            "request_id": str(uuid4()),
            "changes": {"title": "Current title"},
            "base_field_versions": {"title": task["field_versions"]["title"]},
        },
    )
    assert current.status_code == 200, current.text
    stale = client.patch(
        f"/api/v1/tasks/{task_id}",
        headers=headers_b,
        json={
            "request_id": str(uuid4()),
            "changes": {"title": "B proposed title"},
            "base_field_versions": {"title": task["field_versions"]["title"]},
        },
    )
    assert stale.status_code == 409, stale.text
    conflict_id = stale.json()["details"]["conflicts"][0]["id"]
    conflicts = client.get(f"/api/v1/tasks/{task_id}/conflicts", headers=headers_b)
    assert conflicts.status_code == 200, conflicts.text
    assert conflicts.json()[0]["status"] == "OPEN"
    resolved = client.post(
        f"/api/v1/tasks/{task_id}/conflicts/{conflict_id}/resolve",
        headers=headers_a,
        json={"request_id": str(uuid4()), "resolution": "proposed"},
    )
    assert resolved.status_code == 200, resolved.text
    assert resolved.json()["title"] == "B proposed title"
    assert client.get(f"/api/v1/tasks/{task_id}/conflicts", headers=headers_b).json()[0]["status"] == "RESOLVED"

    started = client.post(
        f"/api/v1/tasks/{task_id}/transition",
        headers=headers_a,
        json={"request_id": str(uuid4()), "target_status": "IN_PROGRESS", "base_status_version": resolved.json()["status_version"]},
    )
    assert started.status_code == 200, started.text
    waiting = client.post(
        f"/api/v1/tasks/{task_id}/transition",
        headers=headers_b,
        json={
            "request_id": str(uuid4()),
            "target_status": "WAITING",
            "base_status_version": started.json()["status_version"],
            "blocked_reason": "waiting for review",
            "resume_handler_id": str(user_b_id),
        },
    )
    assert waiting.status_code == 200, waiting.text
    done = client.post(
        f"/api/v1/tasks/{task_id}/transition",
        headers=headers_a,
        json={"request_id": str(uuid4()), "target_status": "DONE", "base_status_version": waiting.json()["status_version"]},
    )
    assert done.status_code == 200, done.text
    assert done.json()["status"] == "DONE"

    comment = client.post(
        f"/api/v1/tasks/{task_id}/comments",
        headers=headers_b,
        json={"request_id": str(uuid4()), "body": "B reviewed the task"},
    )
    assert comment.status_code == 201, comment.text
    comments = client.get(f"/api/v1/tasks/{task_id}/comments", headers=headers_a)
    assert comments.status_code == 200, comments.text
    assert comments.json()[0]["body"] == "B reviewed the task"

    delayed = client.post(
        f"/api/v1/tasks/{task_id}/delays",
        headers=headers_a,
        json={"request_id": str(uuid4()), "new_due_at": "2026-09-01T13:00:00+00:00", "reason": "NO_TIME"},
    )
    assert delayed.status_code == 201, delayed.text
    assert delayed.json()["delay_duration_minutes"] == 60
    delays = client.get(f"/api/v1/tasks/{task_id}/delays", headers=headers_b)
    assert delays.status_code == 200, delays.text
    assert len(delays.json()) == 1

    deleted = client.post(
        f"/api/v1/tasks/{task_id}/lifecycle",
        headers=headers_a,
        json={"request_id": str(uuid4()), "action": "delete", "base_lifecycle_version": done.json()["lifecycle_version"]},
    )
    assert deleted.status_code == 200, deleted.text
    assert deleted.json()["deleted_at"] is not None
    hidden = client.get("/api/v1/workspaces/current/snapshot", headers=headers_b)
    assert hidden.status_code == 200, hidden.text
    assert all(item["id"] != task_id for item in hidden.json()["tasks"])

    restored = client.post(
        f"/api/v1/tasks/{task_id}/restore",
        headers=headers_b,
        json={"request_id": str(uuid4()), "action": "restore", "base_lifecycle_version": deleted.json()["lifecycle_version"]},
    )
    assert restored.status_code == 200, restored.text
    assert restored.json()["deleted_at"] is None
    visible_again = client.get("/api/v1/workspaces/current/snapshot", headers=headers_a)
    assert visible_again.status_code == 200, visible_again.text
    assert any(item["id"] == task_id for item in visible_again.json()["tasks"])
