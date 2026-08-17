from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime, timezone
from hashlib import sha256

from sqlalchemy.orm import Session

from app.auth.passwords import verify_password
from app.auth.session_repository import SessionRepository
from app.auth.tokens import InvalidTokenError, TokenManager
from app.user.models import User
from app.user.repository import UserRepository


class UnauthenticatedError(Exception):
    """Raised when the supplied credentials or refresh session are invalid."""


@dataclass(frozen=True)
class AuthResult:
    user: User
    access_token: str
    refresh_token: str


class AuthService:
    def __init__(
        self,
        session: Session,
        token_manager: TokenManager,
        *,
        clock: Callable[[], datetime] = lambda: datetime.now(timezone.utc),
    ) -> None:
        self.session = session
        self.token_manager = token_manager
        self.clock = clock
        self.users = UserRepository(session)
        self.sessions = SessionRepository(session)

    def login(self, phone: str, password: str) -> AuthResult:
        user = self.users.find_by_phone(phone)
        if user is None or not verify_password(password, user.password_hash):
            raise UnauthenticatedError("invalid credentials")
        return self._create_auth_result(user, self.clock())

    def refresh(self, refresh_token: str) -> AuthResult:
        try:
            claims = self.token_manager.parse_refresh(refresh_token)
        except InvalidTokenError as error:
            raise UnauthenticatedError("invalid refresh token") from error

        now = self.clock()
        stored_session = self.sessions.find_by_refresh_token_hash(_hash_token(refresh_token))
        if (
            stored_session is None
            or stored_session.user_id != claims.user_id
            or stored_session.revoked_at is not None
            or stored_session.expires_at <= now
        ):
            raise UnauthenticatedError("invalid refresh token")

        user = self.users.find_by_id(claims.user_id)
        if user is None:
            raise UnauthenticatedError("invalid refresh token")

        self.sessions.revoke(stored_session, now)
        return self._create_auth_result(user, now)

    def logout(self, refresh_token: str) -> None:
        try:
            self.token_manager.parse_refresh(refresh_token)
        except InvalidTokenError:
            return

        stored_session = self.sessions.find_by_refresh_token_hash(_hash_token(refresh_token))
        if stored_session is not None and stored_session.revoked_at is None:
            self.sessions.revoke(stored_session, self.clock())
            self.session.commit()

    def _create_auth_result(self, user: User, now: datetime) -> AuthResult:
        access_token = self.token_manager.issue_access(user.id, now)
        refresh_token = self.token_manager.issue_refresh(user.id, now)
        refresh_claims = self.token_manager.parse_refresh(refresh_token)
        self.sessions.create(
            user_id=user.id,
            refresh_token_hash=_hash_token(refresh_token),
            expires_at=refresh_claims.expires_at,
            created_at=now,
        )
        self.session.commit()
        return AuthResult(user=user, access_token=access_token, refresh_token=refresh_token)


def _hash_token(token: str) -> str:
    return sha256(token.encode()).hexdigest()
