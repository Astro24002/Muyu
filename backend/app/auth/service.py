from __future__ import annotations

from collections.abc import Callable
import base64
import binascii
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from hashlib import sha256
import secrets
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth.otp import digest_otp, generate_otp, verify_otp
from app.auth.providers.base import SmsDeliveryError, SmsProvider
from app.auth.rate_limit import OtpRateLimitError, OtpRateLimiter, hash_client_ip
from app.db.enums import DeviceStatus, MembershipStatus, UserStatus
from app.db.models import AndroidDevice, MobileSession, SmsVerificationChallenge, User as CloudUser
from app.workspaces.models import WorkspaceMembership


def _hash_token(token: str) -> str:
    return sha256(token.encode()).hexdigest()


class SmsAuthError(Exception):
    def __init__(self, code: str, message: str, status_code: int) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.status_code = status_code


@dataclass(frozen=True)
class MobileAuthResult:
    user: object
    device_id: UUID
    workspace_id: UUID | None
    access_token: str
    refresh_token: str


class SmsAuthService:
    """Cloud SMS authentication service; it never uses password or JWT state."""

    def __init__(
        self,
        session: Session,
        provider: SmsProvider,
        *,
        otp_pepper: str = "local-development-otp-pepper-change-me",
        otp_ttl_seconds: int = 300,
        otp_max_attempts: int = 5,
        phone_window_limit: int = 5,
        ip_window_limit: int = 20,
        mobile_session_ttl_hours: int = 720,
        clock: Callable[[], datetime] = lambda: datetime.now(timezone.utc),
    ) -> None:
        self.session = session
        self.provider = provider
        self.otp_pepper = otp_pepper
        self.otp_ttl_seconds = otp_ttl_seconds
        self.otp_max_attempts = otp_max_attempts
        self.mobile_session_ttl_hours = mobile_session_ttl_hours
        self.clock = clock
        self.rate_limiter = OtpRateLimiter(
            session,
            phone_limit=phone_window_limit,
            ip_limit=ip_window_limit,
        )

    def send_otp(self, phone: str, client_ip: str | None = None) -> int:
        normalized = normalize_phone(phone)
        now = self.clock()
        try:
            self.rate_limiter.check(normalized, client_ip, now)
        except OtpRateLimitError as error:
            raise SmsAuthError("otp_rate_limited", str(error), 429) from error

        code = generate_otp()
        try:
            self.provider.send_otp(normalized, code)
        except SmsDeliveryError as error:
            self.session.rollback()
            raise SmsAuthError("sms_delivery_failed", "SMS delivery failed", 503) from error
        # The local fake provider may be configured with a deterministic test
        # code. Production providers never expose this helper.
        delivered_code = code
        last_code_for = getattr(self.provider, "last_code_for", None)
        if callable(last_code_for):
            delivered_code = str(last_code_for(normalized))
        challenge = SmsVerificationChallenge(
            phone=normalized,
            code_digest=digest_otp(delivered_code, self.otp_pepper),
            request_ip_digest=hash_client_ip(client_ip) if client_ip else None,
            expires_at=now + timedelta(seconds=self.otp_ttl_seconds),
            attempt_count=0,
        )
        self.session.add(challenge)
        self.session.commit()
        return self.otp_ttl_seconds

    def verify_otp(self, phone: str, code: str, device: dict[str, object]) -> MobileAuthResult:
        normalized = normalize_phone(phone)
        now = self.clock()
        challenge = self.session.scalar(
            select(SmsVerificationChallenge)
            .where(
                SmsVerificationChallenge.phone == normalized,
                SmsVerificationChallenge.consumed_at.is_(None),
            )
            .order_by(SmsVerificationChallenge.created_at.desc())
            .with_for_update()
        )
        if (
            challenge is None
            or challenge.expires_at <= now
            or challenge.attempt_count >= self.otp_max_attempts
            or not verify_otp(code, challenge.code_digest, self.otp_pepper)
        ):
            if challenge is not None and challenge.attempt_count < self.otp_max_attempts:
                challenge.attempt_count += 1
                self.session.commit()
            else:
                self.session.rollback()
            raise SmsAuthError("invalid_otp", "invalid or expired OTP", 422)

        challenge.consumed_at = now
        try:
            public_key = base64.b64decode(str(device.get("public_key_der", "")), validate=True)
        except (binascii.Error, ValueError) as error:
            self.session.rollback()
            raise SmsAuthError("invalid_request", "invalid device public key", 422) from error
        if not public_key:
            self.session.rollback()
            raise SmsAuthError("invalid_request", "invalid device public key", 422)

        user = self.session.scalar(select(CloudUser).where(CloudUser.phone == normalized).with_for_update())
        if user is None:
            user = CloudUser(phone=normalized, status=UserStatus.ACTIVE)
            self.session.add(user)
            self.session.flush()
        elif getattr(user, "status", UserStatus.ACTIVE) != UserStatus.ACTIVE:
            self.session.rollback()
            raise SmsAuthError("authentication_required", "user is not active", 401)

        fingerprint = sha256(public_key).hexdigest()
        android_device = self.session.scalar(
            select(AndroidDevice).where(
                AndroidDevice.user_id == user.id,
                AndroidDevice.fingerprint == fingerprint,
            )
        )
        if android_device is None:
            workspace_id = self._workspace_id(user.id)
            android_device = AndroidDevice(
                user_id=user.id,
                public_key_der=public_key,
                fingerprint=fingerprint,
                label=device.get("label") if isinstance(device.get("label"), str) else None,
                status=DeviceStatus.PENDING if workspace_id is not None else DeviceStatus.ACTIVE,
                enrolled_at=now if workspace_id is None else None,
            )
            self.session.add(android_device)
            self.session.flush()
        elif android_device.status == DeviceStatus.REVOKED:
            self.session.rollback()
            raise SmsAuthError("device_not_active", "device is not active", 403)

        token = secrets.token_urlsafe(48)
        self.session.add(
            MobileSession(
                user_id=user.id,
                device_id=android_device.id,
                refresh_token_digest=_hash_token(token),
                expires_at=now + timedelta(hours=self.mobile_session_ttl_hours),
            )
        )
        user.last_login_at = now
        self.session.commit()
        return MobileAuthResult(
            user=user,
            device_id=android_device.id,
            workspace_id=self._workspace_id(user.id),
            access_token=token,
            refresh_token=token,
        )

    def refresh(self, refresh_token: str) -> MobileAuthResult:
        now = self.clock()
        stored = self.session.scalar(
            select(MobileSession).where(MobileSession.refresh_token_digest == _hash_token(refresh_token)).with_for_update()
        )
        if stored is None or stored.revoked_at is not None or stored.expires_at <= now:
            self.session.rollback()
            raise SmsAuthError("mobile_session_expired", "mobile session expired", 401)
        device = self.session.get(AndroidDevice, stored.device_id)
        user = self.session.get(CloudUser, stored.user_id)
        if device is None or device.status != DeviceStatus.ACTIVE:
            self.session.rollback()
            raise SmsAuthError("device_not_active", "device is not active", 403)
        if user is None or getattr(user, "status", UserStatus.ACTIVE) != UserStatus.ACTIVE:
            self.session.rollback()
            raise SmsAuthError("authentication_required", "user is not active", 401)
        stored.revoked_at = now
        token = secrets.token_urlsafe(48)
        self.session.add(
            MobileSession(
                user_id=user.id,
                device_id=device.id,
                refresh_token_digest=_hash_token(token),
                expires_at=now + timedelta(hours=self.mobile_session_ttl_hours),
            )
        )
        self.session.commit()
        return MobileAuthResult(
            user=user,
            device_id=device.id,
            workspace_id=self._workspace_id(user.id),
            access_token=token,
            refresh_token=token,
        )

    def logout(self, session_id: UUID) -> None:
        stored = self.session.get(MobileSession, session_id)
        if stored is not None and stored.revoked_at is None:
            stored.revoked_at = self.clock()
            self.session.commit()

    def _workspace_id(self, user_id: UUID) -> UUID | None:
        membership = self.session.scalar(
            select(WorkspaceMembership).where(
                WorkspaceMembership.user_id == user_id,
                WorkspaceMembership.status == MembershipStatus.ACTIVE,
            )
        )
        return membership.workspace_id if membership else None


def normalize_phone(phone: str) -> str:
    import phonenumbers

    try:
        parsed = phonenumbers.parse(phone, None)
    except phonenumbers.NumberParseException as error:
        raise SmsAuthError("invalid_request", "phone must be an E.164 number", 422) from error
    if not phonenumbers.is_valid_number(parsed) or not phone.strip().startswith("+"):
        raise SmsAuthError("invalid_request", "phone must be an E.164 number", 422)
    return phonenumbers.format_number(parsed, phonenumbers.PhoneNumberFormat.E164)
