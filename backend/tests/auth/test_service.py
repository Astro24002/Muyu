from datetime import datetime, timedelta, timezone
from hashlib import sha256
from uuid import uuid4

import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth.service import AuthService, UnauthenticatedError
from app.auth.tokens import TokenManager
from app.user.models import UserSession
from app.user.service import seed_fixed_users


NOW = datetime.now(timezone.utc).replace(microsecond=0)


def make_service(session: Session) -> AuthService:
    return AuthService(
        session,
        TokenManager(
            access_secret="a" * 32,
            refresh_secret="r" * 32,
            access_ttl=timedelta(minutes=15),
            refresh_ttl=timedelta(days=30),
        ),
        clock=lambda: NOW,
    )


def test_login_persists_only_refresh_token_hash(db_engine) -> None:
    with Session(db_engine) as session:
        seed_fixed_users(session, "shared-password")
        result = make_service(session).login("15028180169", "shared-password")
        sessions = session.scalars(select(UserSession)).all()

        assert result.user.phone == "15028180169"
        assert result.access_token
        assert result.refresh_token
        assert len(sessions) == 1
        assert sessions[0].refresh_token_hash == sha256(result.refresh_token.encode()).hexdigest()
        assert result.refresh_token not in sessions[0].refresh_token_hash


@pytest.mark.parametrize(
    ("phone", "password"),
    [("15028180169", "wrong-password"), ("00000000000", "shared-password")],
)
def test_login_rejects_invalid_credentials(db_engine, phone: str, password: str) -> None:
    with Session(db_engine) as session:
        seed_fixed_users(session, "shared-password")

        with pytest.raises(UnauthenticatedError):
            make_service(session).login(phone, password)

        assert session.scalars(select(UserSession)).all() == []


def test_refresh_revokes_old_session_before_creating_replacement(db_engine) -> None:
    with Session(db_engine) as session:
        seed_fixed_users(session, "shared-password")
        service = make_service(session)
        initial = service.login("15028180169", "shared-password")
        refreshed = service.refresh(initial.refresh_token)
        sessions = session.scalars(select(UserSession)).all()
        old_session = session.scalar(
            select(UserSession).where(UserSession.refresh_token_hash == sha256(initial.refresh_token.encode()).hexdigest())
        )

        assert refreshed.user.id == initial.user.id
        assert refreshed.refresh_token != initial.refresh_token
        assert len(sessions) == 2
        assert old_session is not None
        assert old_session.revoked_at == NOW
        assert sum(stored_session.revoked_at is None for stored_session in sessions) == 1

        with pytest.raises(UnauthenticatedError):
            service.refresh(initial.refresh_token)


def test_refresh_rejects_expired_token(db_engine) -> None:
    with Session(db_engine) as session:
        seed_fixed_users(session, "shared-password")
        service = make_service(session)
        expired_token = TokenManager(
            access_secret="a" * 32,
            refresh_secret="r" * 32,
            access_ttl=timedelta(minutes=15),
            refresh_ttl=timedelta(days=30),
        ).issue_refresh(uuid4(), datetime(2000, 1, 1, tzinfo=timezone.utc))

        with pytest.raises(UnauthenticatedError):
            service.refresh(expired_token)


def test_logout_is_idempotent(db_engine) -> None:
    with Session(db_engine) as session:
        seed_fixed_users(session, "shared-password")
        service = make_service(session)
        result = service.login("15028180169", "shared-password")

        service.logout(result.refresh_token)
        service.logout(result.refresh_token)

        stored_session = session.scalar(select(UserSession))
        assert stored_session is not None
        assert stored_session.revoked_at == NOW
