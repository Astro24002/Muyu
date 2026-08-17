from __future__ import annotations

from collections.abc import Iterator
from uuid import UUID

from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.auth.tokens import InvalidTokenError, TokenManager
from app.httpapi.errors import ApiError


def get_db(request: Request) -> Iterator[Session]:
    engine = getattr(request.app.state, "engine", None)
    if engine is None:
        raise ApiError(503, "SERVICE_UNAVAILABLE", "database is not ready")
    with Session(engine) as session:
        yield session


def get_token_manager(request: Request) -> TokenManager:
    token_manager = getattr(request.app.state, "token_manager", None)
    if token_manager is None:
        raise ApiError(503, "SERVICE_UNAVAILABLE", "authentication is not ready")
    return token_manager


_bearer = HTTPBearer(auto_error=False)


def require_access_token(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
    token_manager: TokenManager = Depends(get_token_manager),
) -> UUID:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise ApiError(401, "UNAUTHORIZED", "authentication required")
    try:
        return token_manager.parse_access(credentials.credentials).user_id
    except InvalidTokenError as error:
        raise ApiError(401, "UNAUTHORIZED", "authentication required") from error
