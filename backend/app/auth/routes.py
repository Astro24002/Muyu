from __future__ import annotations

from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Depends, Response, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy.orm import Session

from app.auth.service import AuthService, UnauthenticatedError
from app.auth.tokens import TokenManager
from app.httpapi.dependencies import get_db, get_token_manager
from app.httpapi.errors import ApiError


class LoginRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    phone: str = Field(min_length=1, max_length=20)
    password: str = Field(min_length=1, max_length=255)


class RefreshRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    refresh_token: str = Field(min_length=1)


class UserResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    phone: str
    nickname: str
    avatar_key: str
    role: str


class AuthResponse(BaseModel):
    user: UserResponse
    access_token: str
    refresh_token: str
    token_type: Literal["bearer"] = "bearer"


router = APIRouter(prefix="/api/auth", tags=["auth"])


@router.post("/login", response_model=AuthResponse)
def login(
    payload: LoginRequest,
    session: Session = Depends(get_db),
    token_manager: TokenManager = Depends(get_token_manager),
) -> AuthResponse:
    try:
        result = AuthService(session, token_manager).login(payload.phone, payload.password)
    except UnauthenticatedError as error:
        raise ApiError(401, "UNAUTHORIZED", "invalid credentials") from error
    return AuthResponse(user=result.user, access_token=result.access_token, refresh_token=result.refresh_token)


@router.post("/refresh", response_model=AuthResponse)
def refresh(
    payload: RefreshRequest,
    session: Session = Depends(get_db),
    token_manager: TokenManager = Depends(get_token_manager),
) -> AuthResponse:
    try:
        result = AuthService(session, token_manager).refresh(payload.refresh_token)
    except UnauthenticatedError as error:
        raise ApiError(401, "UNAUTHORIZED", "invalid refresh token") from error
    return AuthResponse(user=result.user, access_token=result.access_token, refresh_token=result.refresh_token)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(
    payload: RefreshRequest,
    session: Session = Depends(get_db),
    token_manager: TokenManager = Depends(get_token_manager),
) -> Response:
    AuthService(session, token_manager).logout(payload.refresh_token)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
