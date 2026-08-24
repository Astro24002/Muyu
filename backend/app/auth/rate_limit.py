from __future__ import annotations

from datetime import datetime, timedelta, timezone
from hashlib import sha256

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.db.models import SmsVerificationChallenge


class OtpRateLimitError(Exception):
    def __init__(self, retry_after: int) -> None:
        super().__init__("OTP rate limit exceeded")
        self.retry_after = retry_after


class OtpRateLimiter:
    def __init__(self, session: Session, *, phone_limit: int = 5, ip_limit: int = 20, window_seconds: int = 3600) -> None:
        self.session = session
        self.phone_limit = phone_limit
        self.ip_limit = ip_limit
        self.window_seconds = window_seconds

    def check(self, phone: str, client_ip: str | None, now: datetime) -> None:
        # Serialize issuance windows across API instances.  The lock is
        # transaction-scoped and released by the service after the challenge
        # is committed or rolled back.
        self.session.execute(select(func.pg_advisory_xact_lock(func.hashtext(f"otp-phone:{phone}"))))
        if client_ip:
            self.session.execute(
                select(func.pg_advisory_xact_lock(func.hashtext(f"otp-ip:{client_ip}")))
            )
        since = now - timedelta(seconds=self.window_seconds)
        phone_count = self.session.scalar(
            select(func.count(SmsVerificationChallenge.id)).where(
                SmsVerificationChallenge.phone == phone,
                SmsVerificationChallenge.created_at >= since,
            )
        ) or 0
        ip_digest = hash_client_ip(client_ip) if client_ip else None
        ip_count = 0
        if ip_digest:
            ip_count = self.session.scalar(
                select(func.count(SmsVerificationChallenge.id)).where(
                    SmsVerificationChallenge.request_ip_digest == ip_digest,
                    SmsVerificationChallenge.created_at >= since,
                )
            ) or 0
        if phone_count >= self.phone_limit or ip_count >= self.ip_limit:
            raise OtpRateLimitError(self.window_seconds)


def hash_client_ip(client_ip: str) -> str:
    return sha256(client_ip.encode("utf-8")).hexdigest()
