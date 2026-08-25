from __future__ import annotations

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
        import os

        endpoint = os.environ.get("OTP_PROVIDER_URL")
        api_key = os.environ.get("OTP_PROVIDER_API_KEY")
        if not endpoint or not api_key:
            raise ApiError(503, "SERVICE_UNAVAILABLE", "SMS provider is not configured")
        return ProductionSmsProvider(endpoint, api_key)
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
    if device is None or device.status != DeviceStatus.ACTIVE:
        raise ApiError(403, "device_not_active", "device is not active")
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
    )
