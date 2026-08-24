from __future__ import annotations

from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Depends, Response, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth.service import AuthService, UnauthenticatedError
from app.auth.tokens import TokenManager
from app.httpapi.dependencies import get_db, get_token_manager
from app.httpapi.errors import ApiError
from app.auth.dependencies import MobilePrincipal, get_sms_auth_service, require_active_mobile_principal
from app.auth.service import SmsAuthError, SmsAuthService
from app.auth.schemas import (
    MobileAuthResponse,
    MobileRefreshRequest,
    MobileUserResponse,
    SmsSendRequest,
    SmsVerifyRequest,
)
from fastapi import Request


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

mobile_router = APIRouter(prefix="/api/v1", tags=["mobile-auth"])


def _mobile_response(result) -> MobileAuthResponse:
    return MobileAuthResponse(
        user=MobileUserResponse(
            id=result.user.id,
            phone=result.user.phone,
            display_name=result.user.display_name,
            workspace_id=result.workspace_id,
            device_id=result.device_id,
        ),
        access_token=result.access_token,
        refresh_token=result.refresh_token,
    )


@mobile_router.post("/auth/sms/send", status_code=status.HTTP_202_ACCEPTED)
def send_sms_otp(
    payload: SmsSendRequest,
    request: Request,
    http_response: Response,
    service: SmsAuthService = Depends(get_sms_auth_service),
) -> dict[str, object]:
    try:
        client_ip = request.client.host if request.client else None
        expires_in = service.send_otp(payload.phone, client_ip)
    except SmsAuthError as error:
        response = ApiError(error.status_code, error.code, error.message)
        if error.status_code == 429:
            http_response.headers["Retry-After"] = "3600"
            response.details = {"retry_after": 3600}
        raise response
    return {"status": "sent", "expires_in": expires_in}


@mobile_router.post("/auth/sms/verify", response_model=MobileAuthResponse, status_code=status.HTTP_201_CREATED)
def verify_sms_otp(
    payload: SmsVerifyRequest,
    service: SmsAuthService = Depends(get_sms_auth_service),
) -> MobileAuthResponse:
    try:
        result = service.verify_otp(payload.phone, payload.code, payload.device.model_dump())
    except SmsAuthError as error:
        raise ApiError(error.status_code, error.code, error.message) from error
    return _mobile_response(result)


@mobile_router.post("/auth/mobile/refresh", response_model=MobileAuthResponse)
def refresh_mobile_session(
    payload: MobileRefreshRequest,
    service: SmsAuthService = Depends(get_sms_auth_service),
) -> MobileAuthResponse:
    try:
        result = service.refresh(payload.refresh_token)
    except SmsAuthError as error:
        raise ApiError(error.status_code, error.code, error.message) from error
    return _mobile_response(result)


@mobile_router.post("/auth/mobile/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout_mobile_session(
    principal: MobilePrincipal = Depends(require_active_mobile_principal),
    service: SmsAuthService = Depends(get_sms_auth_service),
) -> Response:
    service.logout(principal.session_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@mobile_router.get("/me", response_model=MobileUserResponse)
def get_mobile_me(
    principal: MobilePrincipal = Depends(require_active_mobile_principal),
    session: Session = Depends(get_db),
) -> MobileUserResponse:
    from app.db.enums import MembershipStatus
    from app.db.models import User as CloudUser
    from app.workspaces.models import WorkspaceMembership

    user = session.get(CloudUser, principal.user_id)
    if user is None:
        raise ApiError(401, "authentication_required", "authentication required")
    membership = session.scalar(
        select(WorkspaceMembership).where(
            WorkspaceMembership.user_id == user.id,
            WorkspaceMembership.status == MembershipStatus.ACTIVE,
        )
    )
    return MobileUserResponse(
        id=user.id,
        phone=user.phone,
        display_name=user.display_name,
        workspace_id=membership.workspace_id if membership else None,
        device_id=principal.device_id,
    )


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
