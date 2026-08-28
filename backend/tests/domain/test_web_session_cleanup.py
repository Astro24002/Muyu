from __future__ import annotations

from datetime import datetime, timedelta, timezone
from sqlalchemy.orm import Session

from app.db.enums import ChallengeStatus, DeviceStatus, MembershipStatus, WebSessionStatus
from app.db.models import AndroidDevice, User, WebLoginChallenge, WebSession, Workspace, WorkspaceMembership
from app.web_login.cleanup import purge_expired_sessions


def test_purge_marks_expired_and_deletes_only_old_history(db_engine) -> None:
    now = datetime(2026, 8, 28, tzinfo=timezone.utc)
    with Session(db_engine) as session:
        user = User(phone="+14155552671")
        workspace = Workspace(name="Cleanup")
        device = AndroidDevice(
            user_id=user.id,
            public_key_der=b"device",
            fingerprint="cleanup-device",
            status=DeviceStatus.ACTIVE,
        )
        session.add_all([user, workspace])
        session.flush()
        device.user_id = user.id
        session.add(device)
        session.add(
            WorkspaceMembership(
                workspace_id=workspace.id,
                user_id=user.id,
                member_slot=1,
                status=MembershipStatus.ACTIVE,
            )
        )
        session.flush()
        old = now - timedelta(days=31)
        active = WebSession(
            user_id=user.id,
            workspace_id=workspace.id,
            approving_device_id=device.id,
            session_digest="active-session",
            status=WebSessionStatus.ACTIVE,
            expires_at=now + timedelta(days=1),
        )
        active.updated_at = old
        revoked = WebSession(
            user_id=user.id,
            workspace_id=workspace.id,
            approving_device_id=device.id,
            session_digest="revoked-session",
            status=WebSessionStatus.REVOKED,
            revoked_at=old,
            expires_at=now - timedelta(days=40),
        )
        revoked.updated_at = old
        recent = WebSession(
            user_id=user.id,
            workspace_id=workspace.id,
            approving_device_id=device.id,
            session_digest="recent-session",
            status=WebSessionStatus.REVOKED,
            revoked_at=now - timedelta(days=1),
            expires_at=now - timedelta(days=2),
        )
        challenge = WebLoginChallenge(
            browser_proof_digest="a" * 64,
            scan_nonce_digest="b" * 64,
            safety_code_digest="c" * 64,
            origin="https://muyu.example",
            status=ChallengeStatus.CONSUMED,
            expires_at=old,
        )
        challenge.created_at = old
        pending = WebLoginChallenge(
            browser_proof_digest="d" * 64,
            scan_nonce_digest="e" * 64,
            safety_code_digest="f" * 64,
            origin="https://muyu.example",
            status=ChallengeStatus.PENDING,
            expires_at=now - timedelta(days=40),
        )
        pending.created_at = old
        session.add_all([active, revoked, recent, challenge, pending])
        session.flush()
        active_id = active.id
        revoked_id = revoked.id
        recent_id = recent.id
        challenge_id = challenge.id
        pending_id = pending.id
        session.commit()

        removed = purge_expired_sessions(session, now=now, retention_days=30)
        session.commit()

        assert removed == 3
        assert session.get(WebSession, active_id) is not None
        assert session.get(WebSession, active_id).status == WebSessionStatus.ACTIVE
        assert session.get(WebSession, revoked_id) is None
        assert session.get(WebSession, recent_id) is not None
        assert session.get(WebLoginChallenge, challenge_id) is None
        assert session.get(WebLoginChallenge, pending_id) is None


def test_purge_is_idempotent(db_engine) -> None:
    now = datetime(2026, 8, 28, tzinfo=timezone.utc)
    with Session(db_engine) as session:
        user = User(phone="+14155552672")
        workspace = Workspace(name="Cleanup repeat")
        session.add_all([user, workspace])
        session.flush()
        device = AndroidDevice(
            user_id=user.id,
            public_key_der=b"device-repeat",
            fingerprint="cleanup-repeat",
            status=DeviceStatus.ACTIVE,
        )
        session.add(device)
        session.flush()
        row = WebSession(
            user_id=user.id,
            workspace_id=workspace.id,
            approving_device_id=device.id,
            session_digest="repeat-session",
            status=WebSessionStatus.REVOKED,
            revoked_at=now - timedelta(days=31),
            expires_at=now - timedelta(days=40),
        )
        row.updated_at = now - timedelta(days=31)
        session.add(row)
        session.commit()
        assert purge_expired_sessions(session, now=now, retention_days=30) == 1
        session.commit()
        assert purge_expired_sessions(session, now=now, retention_days=30) == 0
