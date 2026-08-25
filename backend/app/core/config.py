from __future__ import annotations

from functools import lru_cache
from typing import Literal

from pydantic import AnyHttpUrl, Field, PostgresDsn, SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime configuration for the cloud-coordinated API."""

    model_config = SettingsConfigDict(extra="ignore")

    database_url: PostgresDsn = Field(validation_alias="DATABASE_URL")
    public_base_url: AnyHttpUrl = Field(
        default="http://localhost:8080", validation_alias="PUBLIC_BASE_URL"
    )
    web_origin: AnyHttpUrl | None = Field(default=None, validation_alias="WEB_ORIGIN")
    web_cookie_secure: bool = Field(default=False, validation_alias="WEB_COOKIE_SECURE")
    otp_provider: Literal["fake", "production"] = Field(
        default="fake", validation_alias="OTP_PROVIDER"
    )
    otp_provider_url: AnyHttpUrl | None = Field(default=None, validation_alias="OTP_PROVIDER_URL")
    otp_provider_api_key: SecretStr | None = Field(default=None, validation_alias="OTP_PROVIDER_API_KEY")
    fake_otp_code: str | None = Field(default=None, validation_alias="FAKE_OTP_CODE")
    otp_pepper: SecretStr = Field(min_length=32, validation_alias="OTP_PEPPER")
    otp_ttl_seconds: int = Field(default=300, ge=60, le=600, validation_alias="OTP_TTL_SECONDS")
    otp_max_attempts: int = Field(default=5, ge=1, le=10, validation_alias="OTP_MAX_ATTEMPTS")
    otp_phone_window_limit: int = Field(default=5, ge=1, le=20, validation_alias="OTP_PHONE_WINDOW_LIMIT")
    otp_ip_window_limit: int = Field(default=20, ge=1, le=100, validation_alias="OTP_IP_WINDOW_LIMIT")
    mobile_session_ttl_hours: int = Field(
        default=720, ge=1, le=2160, validation_alias="MOBILE_SESSION_TTL_HOURS"
    )
    web_session_ttl_hours: int = Field(
        default=18, ge=1, le=18, validation_alias="WEB_SESSION_TTL_HOURS"
    )
    device_approval_ttl_seconds: int = Field(
        default=600, ge=60, le=3600, validation_alias="DEVICE_APPROVAL_TTL_SECONDS"
    )
    web_login_ttl_seconds: int = Field(
        default=120, ge=30, le=600, validation_alias="WEB_LOGIN_TTL_SECONDS"
    )
    sync_retention_days: int = Field(
        default=30, ge=1, le=365, validation_alias="SYNC_RETENTION_DAYS"
    )
    http_host: str = Field(default="0.0.0.0", validation_alias="HTTP_HOST")
    http_port: int = Field(default=8080, ge=1, le=65535, validation_alias="HTTP_PORT")

    @field_validator("otp_pepper")
    @classmethod
    def reject_short_otp_pepper(cls, value: SecretStr) -> SecretStr:
        if len(value.get_secret_value()) < 32:
            raise ValueError("OTP_PEPPER must contain at least 32 characters")
        return value

    @field_validator("fake_otp_code")
    @classmethod
    def validate_fake_otp_code(cls, value: str | None) -> str | None:
        if value is not None and (len(value) != 6 or not value.isascii() or not value.isdigit()):
            raise ValueError("FAKE_OTP_CODE must be six ASCII digits")
        return value

    @model_validator(mode="after")
    def only_postgresql_is_supported(self) -> "Settings":
        if not self.database_url.unicode_string().startswith("postgresql"):
            raise ValueError("DATABASE_URL must use PostgreSQL")
        if self.otp_provider == "production" and (self.otp_provider_url is None or self.otp_provider_api_key is None):
            raise ValueError("production SMS provider requires OTP_PROVIDER_URL and OTP_PROVIDER_API_KEY")
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()
