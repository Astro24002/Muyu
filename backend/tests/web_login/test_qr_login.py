from datetime import datetime, timedelta, timezone
import hashlib
from uuid import uuid4

import pytest
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from sqlalchemy.orm import Session

from app.db.enums import DeviceStatus, MembershipStatus
from app.db.models import AndroidDevice, User, Workspace, WorkspaceCursor, WorkspaceMembership
from app.devices.signatures import signed_action_payload
from app.web_login.service import WebLoginConflict, WebLoginService


def test_qr_login_approves_and_issues_an_18_hour_session(db_engine) -> None:
    with Session(db_engine) as session:
        user = User(phone="+14155552671")
        workspace = Workspace(name="Shared")
        session.add_all([user, workspace])
        session.flush()
        session.add_all(
            [
                WorkspaceMembership(workspace_id=workspace.id, user_id=user.id, member_slot=1, status=MembershipStatus.ACTIVE),
                WorkspaceCursor(workspace_id=workspace.id, next_cursor=1),
            ]
        )
        private = ec.generate_private_key(ec.SECP256R1())
        der = private.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
        device = AndroidDevice(user_id=user.id, public_key_der=der, fingerprint="device", status=DeviceStatus.ACTIVE)
        session.add(device)
        session.flush()
        now = datetime(2026, 1, 1, tzinfo=timezone.utc)
        proof = "browser-proof-value"
        service = WebLoginService(session, now=lambda: now, safety_cache={}, nonce_cache={})
        challenge = service.create_challenge("https://app.example.test", hashlib.sha256(proof.encode()).hexdigest())
        payload = __import__("json").loads(challenge.qr_payload)
        service.scan(challenge.challenge_id, payload["scan_nonce"], user.id, device.id)
        signed = signed_action_payload(
            action="WEB_LOGIN_APPROVE",
            approval_id=challenge.challenge_id,
            actor_device_id=device.id,
            workspace_id=workspace.id,
            nonce=payload["scan_nonce"].encode(),
            expires_at=challenge.expires_at,
        )
        signature = private.sign(signed, ec.ECDSA(hashes.SHA256()))
        service.approve(challenge.challenge_id, device.id, signature)
        result = service.exchange(challenge.challenge_id, hashlib.sha256(proof.encode()).hexdigest())
        assert result.expires_at == now + timedelta(hours=18)


def test_qr_login_rejects_wrong_browser_proof(db_engine) -> None:
    with Session(db_engine) as session:
        service = WebLoginService(session)
        challenge = service.create_challenge("https://app.example.test", hashlib.sha256(b"proof").hexdigest())
        with pytest.raises(WebLoginConflict) as error:
            service.exchange(challenge.challenge_id, hashlib.sha256(b"different").hexdigest())
        assert error.value.code == "web_login_not_approved"
