from __future__ import annotations

from datetime import datetime
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.user.models import UserSession


class SessionRepository:
    def __init__(self, session: Session) -> None:
        self.session = session

    def create(
        self,
        *,
        user_id: UUID,
        refresh_token_hash: str,
        expires_at: datetime,
        created_at: datetime,
    ) -> UserSession:
        user_session = UserSession(
            user_id=user_id,
            refresh_token_hash=refresh_token_hash,
            expires_at=expires_at,
            created_at=created_at,
        )
        self.session.add(user_session)
        self.session.flush()
        return user_session

    def find_by_refresh_token_hash(self, refresh_token_hash: str) -> UserSession | None:
        return self.session.scalar(select(UserSession).where(UserSession.refresh_token_hash == refresh_token_hash))

    def revoke(self, user_session: UserSession, revoked_at: datetime) -> None:
        user_session.revoked_at = revoked_at
        self.session.flush()
