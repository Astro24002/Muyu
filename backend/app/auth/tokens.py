from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from secrets import token_urlsafe
from uuid import UUID

import jwt


class InvalidTokenError(Exception):
    """Raised when a JWT cannot be trusted for its intended purpose."""


@dataclass(frozen=True)
class AccessClaims:
    user_id: UUID
    token_type: str
    expires_at: datetime


@dataclass(frozen=True)
class RefreshClaims:
    user_id: UUID
    token_type: str
    expires_at: datetime


class TokenManager:
    def __init__(
        self,
        *,
        access_secret: str,
        refresh_secret: str,
        access_ttl: timedelta,
        refresh_ttl: timedelta,
    ) -> None:
        self.access_secret = access_secret
        self.refresh_secret = refresh_secret
        self.access_ttl = access_ttl
        self.refresh_ttl = refresh_ttl

    def issue_access(self, user_id: UUID, now: datetime) -> str:
        return self._issue(user_id, "access", now, self.access_ttl, self.access_secret)

    def issue_refresh(self, user_id: UUID, now: datetime) -> str:
        return self._issue(user_id, "refresh", now, self.refresh_ttl, self.refresh_secret)

    def parse_access(self, token: str) -> AccessClaims:
        return AccessClaims(**self._parse(token, "access", self.access_secret))

    def parse_refresh(self, token: str) -> RefreshClaims:
        return RefreshClaims(**self._parse(token, "refresh", self.refresh_secret))

    @staticmethod
    def _issue(user_id: UUID, token_type: str, now: datetime, ttl: timedelta, secret: str) -> str:
        if now.tzinfo is None:
            raise ValueError("now must be timezone-aware")
        return jwt.encode(
            {
                "sub": str(user_id),
                "type": token_type,
                "iat": now,
                "exp": now + ttl,
                "jti": token_urlsafe(32),
            },
            secret,
            algorithm="HS256",
        )

    @staticmethod
    def _parse(token: str, expected_type: str, secret: str) -> dict[str, object]:
        try:
            payload = jwt.decode(
                token,
                secret,
                algorithms=["HS256"],
                options={"require": ["sub", "type", "iat", "exp"]},
            )
            if payload["type"] != expected_type:
                raise InvalidTokenError("unexpected token type")
            return {
                "user_id": UUID(payload["sub"]),
                "token_type": payload["type"],
                "expires_at": datetime.fromtimestamp(payload["exp"], tz=timezone.utc),
            }
        except (jwt.PyJWTError, KeyError, TypeError, ValueError) as error:
            raise InvalidTokenError("invalid token") from error
