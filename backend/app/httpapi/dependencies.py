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
