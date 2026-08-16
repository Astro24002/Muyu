from __future__ import annotations

from datetime import timedelta
from functools import lru_cache
import re

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


_DURATION_PATTERN = re.compile(r"^(?P<value>[1-9]\d*)(?P<unit>[mhd])$")


class Settings(BaseSettings):
    model_config = SettingsConfigDict(extra="ignore")

    database_url: str = Field(validation_alias="DATABASE_URL")
    auth_password: str = Field(min_length=1, validation_alias="AUTH_PASSWORD")
    jwt_access_secret: str = Field(min_length=32, validation_alias="JWT_ACCESS_SECRET")
    jwt_refresh_secret: str = Field(min_length=32, validation_alias="JWT_REFRESH_SECRET")
    http_host: str = Field(default="0.0.0.0", validation_alias="HTTP_HOST")
    http_port: int = Field(default=8080, ge=1, le=65535, validation_alias="HTTP_PORT")
    access_token_ttl: timedelta = Field(default=timedelta(minutes=15), validation_alias="ACCESS_TOKEN_TTL")
    refresh_token_ttl: timedelta = Field(default=timedelta(days=30), validation_alias="REFRESH_TOKEN_TTL")

    @field_validator("access_token_ttl", "refresh_token_ttl", mode="before")
    @classmethod
    def parse_duration(cls, value: object) -> object:
        if isinstance(value, timedelta):
            return value
        if not isinstance(value, str):
            raise ValueError("duration must use a positive m, h, or d suffix")

        match = _DURATION_PATTERN.fullmatch(value)
        if match is None:
            raise ValueError("duration must use a positive m, h, or d suffix")

        amount = int(match.group("value"))
        unit = match.group("unit")
        return {
            "m": timedelta(minutes=amount),
            "h": timedelta(hours=amount),
            "d": timedelta(days=amount),
        }[unit]


@lru_cache
def get_settings() -> Settings:
    return Settings()
