from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest

from app.auth.tokens import InvalidTokenError, TokenManager


def token_manager() -> TokenManager:
    return TokenManager(
        access_secret="a" * 32,
        refresh_secret="r" * 32,
        access_ttl=timedelta(minutes=15),
        refresh_ttl=timedelta(days=30),
    )


def test_access_token_contains_user_type_and_expiry_claims() -> None:
    manager = token_manager()
    user_id = uuid4()
    now = datetime.now(timezone.utc).replace(microsecond=0)

    claims = manager.parse_access(manager.issue_access(user_id, now))

    assert claims.user_id == user_id
    assert claims.token_type == "access"
    assert claims.expires_at == now + timedelta(minutes=15)


def test_access_token_rejects_wrong_signing_key() -> None:
    user_id = uuid4()
    token = token_manager().issue_access(user_id, datetime.now(timezone.utc))
    wrong_key_manager = TokenManager(
        access_secret="z" * 32,
        refresh_secret="r" * 32,
        access_ttl=timedelta(minutes=15),
        refresh_ttl=timedelta(days=30),
    )

    with pytest.raises(InvalidTokenError):
        wrong_key_manager.parse_access(token)


def test_access_parser_rejects_refresh_token() -> None:
    manager = token_manager()
    token = manager.issue_refresh(uuid4(), datetime.now(timezone.utc))

    with pytest.raises(InvalidTokenError):
        manager.parse_access(token)


def test_access_parser_rejects_expired_token() -> None:
    manager = token_manager()
    expired_token = manager.issue_access(uuid4(), datetime(2000, 1, 1, tzinfo=timezone.utc))

    with pytest.raises(InvalidTokenError):
        manager.parse_access(expired_token)
