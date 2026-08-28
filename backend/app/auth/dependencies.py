from __future__ import annotations

import math
from dataclasses import dataclass
from datetime import datetime, timezone
from uuid import UUID

from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth.providers.base import SmsProvider
from app.auth.providers.fake import FakeSmsProvider
from app.auth.providers.production import ProductionSmsProvider
from app.auth.service import SmsAuthService, SmsAuthError, _hash_token
from app.core.config import get_settings
from app.db.enums import DeviceStatus, UserStatus
from app.db.models import AndroidDevice, MobileSession, User
from app.db.enums import MembershipStatus
from app.workspaces.models import WorkspaceMembership
from app.httpapi.dependencies import get_db
from app.httpapi.errors import ApiError


@dataclass(frozen=True)
class MobilePrincipal:
    user_id: UUID
    device_id: UUID
    session_id: UUID
    workspace_id: UUID | None
    device_status: DeviceStatus
    can_write: bool


_bearer = HTTPBearer(auto_error=False)


def get_sms_provider(request: Request) -> SmsProvider:
    provider = getattr(request.app.state, "sms_provider", None)
    if provider is not None:
        return provider
    settings = getattr(request.app.state, "settings", None)
    if settings is None:
        try:
            settings = get_settings()
        except Exception:
            return FakeSmsProvider()
    if settings.otp_provider == "production":
        if (
            settings.otp_provider_url is None
            or settings.otp_provider_api_key is None
            or settings.otp_sms_sign_id is None
            or settings.otp_sms_template_id is None
        ):
            raise ApiError(503, "SERVICE_UNAVAILABLE", "SMS provider is not configured")
        return ProductionSmsProvider(
            str(settings.otp_provider_url),
            settings.otp_provider_api_key.get_secret_value(),
            sms_sign_id=settings.otp_sms_sign_id,
            template_id=settings.otp_sms_template_id,
            validity_minutes=max(1, math.ceil(settings.otp_ttl_seconds / 60)),
        )
    return FakeSmsProvider()


def get_sms_auth_service(
    request: Request,
    session: Session = Depends(get_db),
    provider: SmsProvider = Depends(get_sms_provider),
) -> SmsAuthService:
    settings = getattr(request.app.state, "settings", None)
    if settings is None:
        try:
            settings = get_settings()
        except Exception:
            settings = None
    kwargs: dict[str, object] = {}
    if settings is not None:
        kwargs = {
            "otp_pepper": settings.otp_pepper.get_secret_value(),
            "otp_ttl_seconds": settings.otp_ttl_seconds,
            "otp_max_attempts": settings.otp_max_attempts,
            "phone_window_limit": settings.otp_phone_window_limit,
            "ip_window_limit": settings.otp_ip_window_limit,
            "mobile_session_ttl_hours": settings.mobile_session_ttl_hours,
        }
    return SmsAuthService(session, provider, **kwargs)


def require_active_mobile_principal(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
    session: Session = Depends(get_db),
) -> MobilePrincipal:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise ApiError(401, "authentication_required", "authentication required")
    stored = session.scalar(
        select(MobileSession).where(MobileSession.refresh_token_digest == _hash_token(credentials.credentials))
    )
    now = datetime.now(timezone.utc)
    if stored is None or stored.revoked_at is not None or stored.expires_at <= now:
        raise ApiError(401, "mobile_session_expired", "mobile session expired")
    device = session.get(AndroidDevice, stored.device_id)
    user = session.get(User, stored.user_id)
    if device is None or device.status == DeviceStatus.REVOKED:
        raise ApiError(403, "device_not_active", "device is not active")
    if device.status != DeviceStatus.ACTIVE:
        raise ApiError(403, "device_not_verified", "device has not been verified")
    if user is None or user.status != UserStatus.ACTIVE:
        raise ApiError(401, "authentication_required", "authentication required")
    membership = session.scalar(
        select(WorkspaceMembership).where(
            WorkspaceMembership.user_id == user.id,
            WorkspaceMembership.status == MembershipStatus.ACTIVE,
        )
    )
    return MobilePrincipal(
        user_id=user.id,
        device_id=device.id,
        session_id=stored.id,
        workspace_id=membership.workspace_id if membership else None,
        device_status=device.status,
        can_write=True,
    )


def require_mobile_principal(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
    session: Session = Depends(get_db),
) -> MobilePrincipal:
    """Resolve a mobile session before device approval is complete.

    A pending device receives only the enrollment-request surface. All normal
    workspace APIs continue to depend on ``require_active_mobile_principal``.
    """
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise ApiError(401, "authentication_required", "authentication required")
    stored = session.scalar(
        select(MobileSession).where(MobileSession.refresh_token_digest == _hash_token(credentials.credentials))
    )
    now = datetime.now(timezone.utc)
    if stored is None or stored.revoked_at is not None or stored.expires_at <= now:
        raise ApiError(401, "mobile_session_expired", "mobile session expired")
    device = session.get(AndroidDevice, stored.device_id)
    user = session.get(User, stored.user_id)
    if device is None or device.status == DeviceStatus.REVOKED or user is None or user.status != UserStatus.ACTIVE:
        raise ApiError(401, "authentication_required", "authentication required")
    membership = session.scalar(
        select(WorkspaceMembership).where(
            WorkspaceMembership.user_id == user.id,
            WorkspaceMembership.status == MembershipStatus.ACTIVE,
        )
    )
    return MobilePrincipal(
        user_id=user.id,
        device_id=device.id,
        session_id=stored.id,
        workspace_id=membership.workspace_id if membership else None,
        device_status=device.status,
        can_write=device.status == DeviceStatus.ACTIVE,
    )
