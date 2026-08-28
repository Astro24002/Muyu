from __future__ import annotations

from datetime import datetime, timezone
from dataclasses import dataclass
from uuid import UUID

from fastapi import Cookie, Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.enums import WebSessionStatus
from app.db.models import AndroidDevice, WebSession
from app.auth.dependencies import MobilePrincipal, require_active_mobile_principal
from app.httpapi.dependencies import get_db
from app.httpapi.errors import ApiError
from app.web_login.service import _digest


@dataclass(frozen=True)
class WebPrincipal:
    user_id: UUID
    workspace_id: UUID
    session_id: UUID
    approving_device_id: UUID


_bearer = HTTPBearer(auto_error=False)


def require_web_or_active_mobile_principal(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
    session_cookie: str | None = Cookie(default=None, alias="muyu_web_session"),
    session: Session = Depends(get_db),
) -> WebPrincipal | MobilePrincipal:
    """Resolve the read/manage surface for both supported session types.

    Android remains the authority for workspace-wide WebSession revocation.
    A browser may only address its own session, which lets the Web session
    page render and end the current login without granting device privileges.
    """

    if credentials is not None:
        return require_active_mobile_principal(credentials, session)
    return require_web_principal(session_cookie, session)


def require_web_principal(
    session_cookie: str | None = Cookie(default=None, alias="muyu_web_session"),
    session: Session = Depends(get_db),
) -> WebPrincipal:
    if not session_cookie:
        raise ApiError(401, "authentication_required", "web authentication required")
    stored = session.scalar(select(WebSession).where(WebSession.session_digest == _digest(session_cookie)))
    if stored is None or stored.status != WebSessionStatus.ACTIVE or stored.revoked_at is not None:
        raise ApiError(401, "web_session_expired", "web session expired")
    if stored.expires_at <= datetime.now(timezone.utc):
        stored.status = WebSessionStatus.EXPIRED
        session.commit()
        raise ApiError(401, "web_session_expired", "web session expired")
    device = session.get(AndroidDevice, stored.approving_device_id)
    if device is None or device.status.value != "ACTIVE":
        stored.status = WebSessionStatus.REVOKED
        stored.revoked_at = datetime.now(timezone.utc)
        session.commit()
        raise ApiError(401, "web_session_expired", "web session expired")
    return WebPrincipal(stored.user_id, stored.workspace_id, stored.id, stored.approving_device_id)
