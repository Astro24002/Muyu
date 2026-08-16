from datetime import timedelta

import pytest
from pydantic import ValidationError

from app.core.config import Settings


def environment(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("DATABASE_URL", "postgresql+psycopg://muyu:secret@db:5432/muyu")
    monkeypatch.setenv("AUTH_PASSWORD", "shared-password")
    monkeypatch.setenv("JWT_ACCESS_SECRET", "01234567890123456789012345678901")
    monkeypatch.setenv("JWT_REFRESH_SECRET", "abcdefghijklmnopqrstuvwxyz123456")


def test_settings_parse_complete_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    environment(monkeypatch)
    monkeypatch.setenv("HTTP_HOST", "127.0.0.1")
    monkeypatch.setenv("HTTP_PORT", "9090")
    monkeypatch.setenv("ACCESS_TOKEN_TTL", "20m")
    monkeypatch.setenv("REFRESH_TOKEN_TTL", "48h")

    settings = Settings()

    assert settings.database_url == "postgresql+psycopg://muyu:secret@db:5432/muyu"
    assert settings.auth_password == "shared-password"
    assert settings.http_host == "127.0.0.1"
    assert settings.http_port == 9090
    assert settings.access_token_ttl == timedelta(minutes=20)
    assert settings.refresh_token_ttl == timedelta(hours=48)


def test_settings_apply_runtime_defaults(monkeypatch: pytest.MonkeyPatch) -> None:
    environment(monkeypatch)

    settings = Settings()

    assert settings.http_host == "0.0.0.0"
    assert settings.http_port == 8080
    assert settings.access_token_ttl == timedelta(minutes=15)
    assert settings.refresh_token_ttl == timedelta(days=30)


@pytest.mark.parametrize(
    "name",
    ["DATABASE_URL", "AUTH_PASSWORD", "JWT_ACCESS_SECRET", "JWT_REFRESH_SECRET"],
)
def test_settings_reject_missing_required_value(monkeypatch: pytest.MonkeyPatch, name: str) -> None:
    environment(monkeypatch)
    monkeypatch.delenv(name)

    with pytest.raises(ValidationError):
        Settings()


def test_settings_reject_invalid_duration(monkeypatch: pytest.MonkeyPatch) -> None:
    environment(monkeypatch)
    monkeypatch.setenv("ACCESS_TOKEN_TTL", "not-a-duration")

    with pytest.raises(ValidationError):
        Settings()


def test_settings_reject_short_secret(monkeypatch: pytest.MonkeyPatch) -> None:
    environment(monkeypatch)
    monkeypatch.setenv("JWT_REFRESH_SECRET", "too-short")

    with pytest.raises(ValidationError):
        Settings()
