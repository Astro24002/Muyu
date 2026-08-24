import pytest
from pydantic import ValidationError

from app.core.config import Settings


def environment(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("DATABASE_URL", "postgresql+psycopg://muyu:secret@db:5432/muyu")
    monkeypatch.setenv("OTP_PEPPER", "test-otp-pepper-with-sufficient-length")


def test_settings_parse_cloud_environment_without_legacy_password_or_jwt(monkeypatch: pytest.MonkeyPatch) -> None:
    environment(monkeypatch)
    monkeypatch.setenv("HTTP_HOST", "127.0.0.1")
    monkeypatch.setenv("HTTP_PORT", "9090")
    monkeypatch.setenv("PUBLIC_BASE_URL", "https://muyu.example")
    monkeypatch.setenv("OTP_PROVIDER", "fake")

    settings = Settings()

    assert settings.database_url.unicode_string() == "postgresql+psycopg://muyu:secret@db:5432/muyu"
    assert settings.http_host == "127.0.0.1"
    assert settings.http_port == 9090
    assert str(settings.public_base_url) == "https://muyu.example/"
    assert settings.otp_provider == "fake"


def test_settings_apply_runtime_defaults(monkeypatch: pytest.MonkeyPatch) -> None:
    environment(monkeypatch)

    settings = Settings()

    assert settings.http_host == "0.0.0.0"
    assert settings.http_port == 8080
    assert settings.otp_ttl_seconds == 300
    assert settings.web_session_ttl_hours == 18


@pytest.mark.parametrize(
    "name",
    ["DATABASE_URL", "OTP_PEPPER"],
)
def test_settings_reject_missing_required_value(monkeypatch: pytest.MonkeyPatch, name: str) -> None:
    environment(monkeypatch)
    monkeypatch.delenv(name)

    with pytest.raises(ValidationError):
        Settings()


def test_settings_reject_sqlite(monkeypatch: pytest.MonkeyPatch) -> None:
    environment(monkeypatch)
    monkeypatch.setenv("DATABASE_URL", "sqlite:////tmp/muyu-test.db")

    with pytest.raises(ValidationError):
        Settings()


def test_settings_reject_web_session_longer_than_eighteen_hours(monkeypatch: pytest.MonkeyPatch) -> None:
    environment(monkeypatch)
    monkeypatch.setenv("WEB_SESSION_TTL_HOURS", "19")

    with pytest.raises(ValidationError):
        Settings()
