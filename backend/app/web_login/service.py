from __future__ import annotations

import base64
import hashlib
import hmac
import json
import secrets
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Callable
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.enums import ChallengeStatus, DeviceStatus, MembershipStatus, WebSessionStatus
from app.db.models import ActivityEvent, AndroidDevice, User, WebLoginChallenge, WebSession, WorkspaceMembership
from app.devices.signatures import signed_action_payload, verify_device_signature


class WebLoginConflict(Exception):
    def __init__(self, code: str, message: str, status_code: int = 422) -> None:
        super().__init__(message)
        self.code = code
        self.status_code = status_code


@dataclass(frozen=True)
class BrowserChallenge:
    challenge_id: UUID
    qr_payload: str
    origin: str
    safety_code: str
    expires_at: datetime


@dataclass(frozen=True)
class WebSessionResult:
    session_id: UUID
    raw_cookie: str
    expires_at: datetime


@dataclass(frozen=True)
class WebSessionSummary:
    id: UUID
    status: WebSessionStatus
    origin: str | None
    created_at: datetime
    expires_at: datetime

    def as_dict(self) -> dict[str, object]:
        return {
            "id": str(self.id),
            "status": self.status.value,
            "origin": self.origin,
            "created_at": self.created_at.isoformat(),
            "expires_at": self.expires_at.isoformat(),
        }


class WebSessionConflict(Exception):
    def __init__(self, code: str, message: str, status_code: int = 409) -> None:
        super().__init__(message)
        self.code = code
        self.status_code = status_code


class WebSessionService:
    """Manage temporary browser sessions from a verified Android device."""

    def __init__(
        self,
        session: Session,
        *,
        now: Callable[[], datetime] = lambda: datetime.now(timezone.utc),
    ) -> None:
        self.session = session
        self.now = now

    def list_active(self, workspace_id: UUID) -> list[WebSessionSummary]:
        rows = self.session.scalars(
            select(WebSession)
            .where(
                WebSession.workspace_id == workspace_id,
                WebSession.status == WebSessionStatus.ACTIVE,
                WebSession.expires_at > self.now(),
            )
            .order_by(WebSession.created_at.desc(), WebSession.id.desc())
        ).all()
        return [
            WebSessionSummary(
                id=row.id,
                status=row.status,
                origin=row.origin,
                created_at=row.created_at,
                expires_at=row.expires_at,
            )
            for row in rows
        ]

    def revoke(self, session_id: UUID, workspace_id: UUID, actor_device_id: UUID) -> None:
        actor_user_id = self._authorize_actor(workspace_id, actor_device_id)
        row = self.session.scalar(
            select(WebSession)
            .where(WebSession.id == session_id, WebSession.workspace_id == workspace_id)
            .with_for_update()
        )
        if row is None:
            raise WebSessionConflict("approval_not_allowed", "session revocation is not authorized", 403)
        if row.status == WebSessionStatus.REVOKED:
            raise WebSessionConflict("web_session_already_revoked", "web session is already revoked", 409)
        if row.status == WebSessionStatus.EXPIRED or row.expires_at <= self.now():
            row.status = WebSessionStatus.EXPIRED
            row.updated_at = self.now()
            raise WebSessionConflict("web_session_expired", "web session is expired", 409)
        row.status = WebSessionStatus.REVOKED
        row.revoked_at = self.now()
        row.updated_at = self.now()
        self._audit(workspace_id, actor_user_id, "web_session_revoked", row.id)

    def revoke_all(self, workspace_id: UUID, actor_device_id: UUID) -> int:
        actor_user_id = self._authorize_actor(workspace_id, actor_device_id)
        now = self.now()
        rows = self.session.scalars(
            select(WebSession)
            .where(
                WebSession.workspace_id == workspace_id,
                WebSession.status == WebSessionStatus.ACTIVE,
                WebSession.expires_at > now,
            )
            .with_for_update()
        ).all()
        for row in rows:
            row.status = WebSessionStatus.REVOKED
            row.revoked_at = now
            row.updated_at = now
            self._audit(workspace_id, actor_user_id, "web_session_revoked", row.id)
        return len(rows)

    def revoke_own(self, session_id: UUID, user_id: UUID, workspace_id: UUID) -> None:
        """End the browser session making the request.

        This intentionally has a narrower authority than ``revoke``: a Web
        session can log itself out, but only an ACTIVE Android device may
        revoke another browser session or all sessions in a workspace.
        """

        row = self.session.scalar(
            select(WebSession)
            .where(
                WebSession.id == session_id,
                WebSession.user_id == user_id,
                WebSession.workspace_id == workspace_id,
            )
            .with_for_update()
        )
        if row is None:
            raise WebSessionConflict("approval_not_allowed", "session revocation is not authorized", 403)
        if row.status == WebSessionStatus.REVOKED:
            raise WebSessionConflict("web_session_already_revoked", "web session is already revoked", 409)
        if row.status == WebSessionStatus.EXPIRED or row.expires_at <= self.now():
            row.status = WebSessionStatus.EXPIRED
            row.updated_at = self.now()
            raise WebSessionConflict("web_session_expired", "web session is expired", 409)
        row.status = WebSessionStatus.REVOKED
        row.revoked_at = self.now()
        row.updated_at = self.now()
        self._audit(workspace_id, user_id, "web_session_self_revoked", row.id)

    def _authorize_actor(self, workspace_id: UUID, actor_device_id: UUID) -> UUID:
        device = self.session.get(AndroidDevice, actor_device_id)
        if device is None or device.status != DeviceStatus.ACTIVE:
            raise WebSessionConflict("device_not_active", "device is not active", 403)
        member = self.session.scalar(
            select(WorkspaceMembership.id).where(
                WorkspaceMembership.workspace_id == workspace_id,
                WorkspaceMembership.user_id == device.user_id,
                WorkspaceMembership.status == MembershipStatus.ACTIVE,
            )
        )
        if member is None:
            raise WebSessionConflict("workspace_access_denied", "active workspace membership required", 403)
        return device.user_id

    def _audit(self, workspace_id: UUID, actor_user_id: UUID, action: str, subject_id: UUID) -> None:
        self.session.add(
            ActivityEvent(
                workspace_id=workspace_id,
                actor_user_id=actor_user_id,
                event_type=action,
                payload={"subject_id": str(subject_id)},
            )
        )


class WebLoginService:
    def __init__(
        self,
        session: Session,
        *,
        now: Callable[[], datetime] = lambda: datetime.now(timezone.utc),
        ttl_seconds: int = 120,
        session_ttl_hours: int = 18,
        safety_cache: dict[str, str] | None = None,
        nonce_cache: dict[str, bytes] | None = None,
        allowed_origin: str | None = None,
    ) -> None:
        self.session = session
        self.now = now
        self.ttl_seconds = min(600, max(30, ttl_seconds))
        self.session_ttl_hours = min(18, max(1, session_ttl_hours))
        self.safety_cache = safety_cache if safety_cache is not None else {}
        self.nonce_cache = nonce_cache if nonce_cache is not None else {}
        self.allowed_origin = allowed_origin.rstrip("/") if allowed_origin else None

    def create_challenge(self, origin: str, browser_proof_hash: str) -> BrowserChallenge:
        if not origin.startswith(("https://", "http://localhost", "http://127.0.0.1")):
            raise WebLoginConflict("invalid_request", "origin is not allowed")
        if self.allowed_origin is not None and origin.rstrip("/") != self.allowed_origin:
            raise WebLoginConflict("invalid_request", "origin is not configured")
        if len(browser_proof_hash) != 64:
            raise WebLoginConflict("invalid_request", "browser proof hash is invalid")
        nonce = secrets.token_urlsafe(32)
        safety_code = f"{secrets.randbelow(1_000_000):06d}"
        expires_at = self.now() + timedelta(seconds=self.ttl_seconds)
        challenge = WebLoginChallenge(
            browser_proof_digest=browser_proof_hash,
            scan_nonce_digest=_digest(nonce),
            safety_code_digest=_digest(safety_code),
            origin=origin,
            status=ChallengeStatus.PENDING,
            expires_at=expires_at,
        )
        self.session.add(challenge)
        self.session.flush()
        self.safety_cache[str(challenge.id)] = safety_code
        self.nonce_cache[str(challenge.id)] = nonce.encode("utf-8")
        payload = {
            "version": 1,
            "challenge_id": str(challenge.id),
            "scan_nonce": nonce,
            "origin": origin,
            "expires_at": expires_at.isoformat(),
        }
        return BrowserChallenge(
            challenge_id=challenge.id,
            qr_payload=json.dumps(payload, separators=(",", ":"), sort_keys=True),
            origin=origin,
            safety_code=safety_code,
            expires_at=expires_at,
        )

    def scan(self, challenge_id: UUID, scan_nonce: str, user_id: UUID, device_id: UUID) -> dict[str, object]:
        challenge = self._pending(challenge_id)
        if not hmac.compare_digest(challenge.scan_nonce_digest, _digest(scan_nonce)):
            raise WebLoginConflict("web_login_proof_invalid", "scan nonce is invalid", 401)
        if challenge.user_id is not None and (challenge.user_id != user_id or challenge.approving_device_id != device_id):
            raise WebLoginConflict("approval_not_allowed", "challenge is already assigned", 403)
        device = self.session.get(AndroidDevice, device_id)
        if device is None or device.user_id != user_id or device.status != DeviceStatus.ACTIVE:
            raise WebLoginConflict("device_not_active", "device is not active", 403)
        workspace_id = self.session.scalar(
            select(WorkspaceMembership.workspace_id).where(
                WorkspaceMembership.user_id == user_id,
                WorkspaceMembership.status == MembershipStatus.ACTIVE,
            )
        )
        if workspace_id is None:
            raise WebLoginConflict("workspace_access_denied", "workspace membership required", 403)
        challenge.user_id = user_id
        challenge.workspace_id = workspace_id
        challenge.approving_device_id = device_id
        self.session.flush()
        signature_payload = signed_action_payload(
            action="WEB_LOGIN_APPROVE",
            approval_id=challenge.id,
            actor_device_id=device_id,
            workspace_id=workspace_id,
            nonce=scan_nonce.encode("utf-8"),
            expires_at=challenge.expires_at,
        )
        return {
            "id": str(challenge.id),
            "status": challenge.status.value,
            "origin": challenge.origin,
            "safety_code": self.safety_cache.get(str(challenge.id), "000000"),
            "signature_payload": base64.urlsafe_b64encode(signature_payload).rstrip(b"=").decode("ascii"),
            "expires_at": challenge.expires_at.isoformat(),
        }

    def approve(self, challenge_id: UUID, device_id: UUID, signature: bytes, scan_nonce: str | None = None) -> None:
        challenge = self._pending(challenge_id)
        if challenge.status != ChallengeStatus.PENDING:
            raise WebLoginConflict("lifecycle_conflict", "challenge has already been approved", 409)
        if challenge.approving_device_id != device_id:
            raise WebLoginConflict("approval_not_allowed", "wrong approving device", 403)
        device = self.session.get(AndroidDevice, device_id)
        if device is None or device.status != DeviceStatus.ACTIVE or challenge.user_id is None or challenge.workspace_id is None:
            raise WebLoginConflict("approval_not_allowed", "approval is not allowed", 403)
        nonce = (scan_nonce.encode("utf-8") if scan_nonce else self.nonce_cache.get(str(challenge.id)))
        if nonce is None:
            raise WebLoginConflict("web_login_proof_invalid", "scan nonce is unavailable", 401)
        payload = signed_action_payload(
            action="WEB_LOGIN_APPROVE",
            approval_id=challenge.id,
            actor_device_id=device_id,
            workspace_id=challenge.workspace_id,
            nonce=nonce,
            expires_at=challenge.expires_at,
        )
        valid = verify_device_signature(device.public_key_der, payload, signature)
        if not valid:
            raise WebLoginConflict("invalid_device_signature", "invalid device signature")
        challenge.status = ChallengeStatus.APPROVED
        challenge.approved_at = self.now()
        self.session.flush()

    def exchange(self, challenge_id: UUID, browser_proof: str) -> WebSessionResult:
        challenge = self.session.scalar(select(WebLoginChallenge).where(WebLoginChallenge.id == challenge_id).with_for_update())
        if challenge is None or challenge.expires_at <= self.now():
            raise WebLoginConflict("web_login_expired", "web login challenge expired", 410)
        if challenge.status != ChallengeStatus.APPROVED or challenge.user_id is None or challenge.workspace_id is None or challenge.approving_device_id is None:
            raise WebLoginConflict("web_login_not_approved", "web login is not approved", 401)
        # The browser sends the raw proof at the protocol boundary.  Accept
        # the already-hashed form used by the Flutter transport as well, but
        # compare both representations in constant time.
        provided_digest = browser_proof if len(browser_proof) == 64 else _digest(browser_proof)
        if not hmac.compare_digest(challenge.browser_proof_digest, provided_digest):
            raise WebLoginConflict("web_login_proof_invalid", "browser proof is invalid", 401)
        challenge.status = ChallengeStatus.CONSUMED
        challenge.consumed_at = self.now()
        raw_cookie = secrets.token_urlsafe(48)
        # A successful exchange receives the full bounded Web-session
        # lifetime; the short QR challenge lifetime must not shorten it.
        expires_at = self.now() + timedelta(hours=self.session_ttl_hours)
        web_session = WebSession(
            user_id=challenge.user_id,
            workspace_id=challenge.workspace_id,
            approving_device_id=challenge.approving_device_id,
            session_digest=_digest(raw_cookie),
            status=WebSessionStatus.ACTIVE,
            origin=challenge.origin,
            expires_at=expires_at,
        )
        self.session.add(web_session)
        self.session.flush()
        return WebSessionResult(session_id=web_session.id, raw_cookie=raw_cookie, expires_at=expires_at)

    def revoke(self, session_id: UUID, owner_user_id: UUID) -> None:
        web_session = self.session.scalar(select(WebSession).where(WebSession.id == session_id).with_for_update())
        if web_session is None or web_session.user_id != owner_user_id:
            raise WebLoginConflict("approval_not_allowed", "session revocation is not authorized", 403)
        web_session.status = WebSessionStatus.REVOKED
        web_session.revoked_at = self.now()

    def _pending(self, challenge_id: UUID) -> WebLoginChallenge:
        challenge = self.session.scalar(select(WebLoginChallenge).where(WebLoginChallenge.id == challenge_id).with_for_update())
        if challenge is None or challenge.status not in {ChallengeStatus.PENDING, ChallengeStatus.APPROVED}:
            raise WebLoginConflict("web_login_expired", "web login challenge expired", 410)
        if challenge.expires_at <= self.now():
            challenge.status = ChallengeStatus.EXPIRED
            raise WebLoginConflict("web_login_expired", "web login challenge expired", 410)
        return challenge


def _digest(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()
