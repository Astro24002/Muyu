from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, Response, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.httpapi.dependencies import get_db
from app.httpapi.errors import ApiError
from app.auth.dependencies import MobilePrincipal, get_sms_auth_service, require_active_mobile_principal, require_mobile_principal
from app.auth.service import SmsAuthError, SmsAuthService
from app.auth.profile import ProfileService, public_display_name
from app.db.enums import MembershipStatus
from app.workspaces.models import WorkspaceMembership
from app.workspaces.bootstrap_schemas import public_device_status
from app.auth.schemas import (
    MobileAuthResponse,
    MobileRefreshRequest,
    MobileUserResponse,
    ProfileUpdateRequest,
    SmsSendRequest,
    SmsVerifyRequest,
)
from fastapi import Request


mobile_router = APIRouter(prefix="/api/v1", tags=["mobile-auth"])


def _mobile_response(result) -> MobileAuthResponse:
    return MobileAuthResponse(
        user=MobileUserResponse(
            id=result.user.id,
            phone=result.user.phone,
            display_name=public_display_name(result.user),
            workspace_id=result.workspace_id,
            device_id=result.device_id,
            device_status=public_device_status(result.device_status),
            can_write=result.can_write,
        ),
        device_id=result.device_id,
        access_token=result.access_token,
        refresh_token=result.refresh_token,
        device_status=public_device_status(result.device_status),
        can_write=result.can_write,
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
    principal: MobilePrincipal = Depends(require_mobile_principal),
    session: Session = Depends(get_db),
) -> MobileUserResponse:
    from app.db.models import User as CloudUser

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
        display_name=public_display_name(user),
        workspace_id=membership.workspace_id if membership else None,
        device_id=principal.device_id,
        device_status=public_device_status(principal.device_status),
        can_write=principal.can_write,
    )


@mobile_router.patch("/me", response_model=MobileUserResponse)
def update_mobile_me(
    payload: ProfileUpdateRequest,
    principal: MobilePrincipal = Depends(require_active_mobile_principal),
    session: Session = Depends(get_db),
) -> MobileUserResponse:
    try:
        user = ProfileService(session).update_display_name(
            principal.user_id,
            payload.display_name,
        )
        session.commit()
    except LookupError as error:
        session.rollback()
        raise ApiError(401, "authentication_required", "authentication required") from error

    membership = session.scalar(
        select(WorkspaceMembership).where(
            WorkspaceMembership.user_id == user.id,
            WorkspaceMembership.status == MembershipStatus.ACTIVE,
        )
    )
    return MobileUserResponse(
        id=user.id,
        phone=user.phone,
        display_name=public_display_name(user),
        workspace_id=membership.workspace_id if membership else None,
        device_id=principal.device_id,
        device_status=public_device_status(principal.device_status),
        can_write=principal.can_write,
    )
