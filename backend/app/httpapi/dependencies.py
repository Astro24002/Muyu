from __future__ import annotations

from collections.abc import Iterator
from fastapi import Depends, Request
from sqlalchemy.orm import Session

from app.httpapi.errors import ApiError


def get_db(request: Request) -> Iterator[Session]:
    engine = getattr(request.app.state, "engine", None)
    if engine is None:
        raise ApiError(503, "SERVICE_UNAVAILABLE", "database is not ready")
    with Session(engine) as session:
        yield session


SUPPORTED_CLIENT_CONTRACT = "2026-09-v1"


def client_contract(request: Request) -> str | None:
    """Validate the optional client contract marker used during compatibility rollout."""
    value = request.headers.get("x-muyu-client-contract")
    if value is None or value.strip() == "":
        return None
    value = value.strip()
    if value != SUPPORTED_CLIENT_CONTRACT:
        raise ApiError(400, "unsupported_client_contract", "unsupported client contract")
    return value
