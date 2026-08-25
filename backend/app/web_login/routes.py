from __future__ import annotations

import base64
import hashlib
from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, Request, Response, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy.orm import Session

from app.auth.dependencies import MobilePrincipal, require_active_mobile_principal
from app.db.enums import WebSessionStatus
from app.db.models import WebLoginChallenge, WebSession
from app.httpapi.dependencies import get_db
from app.httpapi.errors import ApiError
from app.web_login.dependencies import WebPrincipal, require_web_principal
from app.web_login.service import WebLoginConflict, WebLoginService


class CreateChallengeBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    origin: str
    browser_proof_hash: str = Field(min_length=64, max_length=64)


class ScanBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    scan_nonce: str = Field(min_length=1, max_length=512)


class ApproveBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    signature: str = Field(min_length=1, max_length=4096)
    scan_nonce: str | None = None


class ExchangeBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    browser_proof: str = Field(min_length=16, max_length=512)


router = APIRouter(prefix="/api/v1/web-login", tags=["web-login"])
sessions_router = APIRouter(prefix="/api/v1/web-sessions", tags=["web-sessions"])


def _service(request: Request, session: Session) -> WebLoginService:
    settings = getattr(request.app.state, "settings", None)
    ttl = getattr(settings, "web_login_ttl_seconds", 120)
    session_ttl = getattr(settings, "web_session_ttl_hours", 18)
    allowed_origin = str(settings.web_origin).rstrip("/") if getattr(settings, "web_origin", None) else None
    safety_cache = getattr(request.app.state, "web_login_safety_codes", None)
    if safety_cache is None:
        safety_cache = request.app.state.web_login_safety_codes = {}
    nonce_cache = getattr(request.app.state, "web_login_nonces", None)
    if nonce_cache is None:
        nonce_cache = request.app.state.web_login_nonces = {}
    return WebLoginService(
        session,
        ttl_seconds=ttl,
        session_ttl_hours=session_ttl,
        safety_cache=safety_cache,
        nonce_cache=nonce_cache,
        allowed_origin=allowed_origin,
    )


def _error(error: WebLoginConflict) -> ApiError:
    return ApiError(error.status_code, error.code, str(error))


@router.post("/challenges", status_code=status.HTTP_201_CREATED)
def create_challenge(body: CreateChallengeBody, request: Request, session: Session = Depends(get_db)) -> dict[str, object]:
    try:
        challenge = _service(request, session).create_challenge(body.origin, body.browser_proof_hash)
        session.commit()
    except WebLoginConflict as error:
        session.rollback()
        raise _error(error) from error
    return {"challenge_id": str(challenge.challenge_id), "qr_payload": challenge.qr_payload, "origin": challenge.origin, "safety_code": challenge.safety_code, "expires_at": challenge.expires_at.isoformat()}


@router.get("/challenges/{challenge_id}")
def challenge_status(challenge_id: UUID, session: Session = Depends(get_db)) -> dict[str, object]:
    challenge = session.get(WebLoginChallenge, challenge_id)
    if challenge is None:
        raise ApiError(404, "not_found", "challenge not found")
    return {"challenge_id": str(challenge.id), "status": challenge.status.value, "expires_at": challenge.expires_at.isoformat()}


@router.post("/challenges/{challenge_id}/scan")
def scan_challenge(challenge_id: UUID, body: ScanBody, request: Request, principal: MobilePrincipal = Depends(require_active_mobile_principal), session: Session = Depends(get_db)) -> dict[str, object]:
    try:
        result = _service(request, session).scan(challenge_id, body.scan_nonce, principal.user_id, principal.device_id)
        session.commit()
    except WebLoginConflict as error:
        session.rollback()
        raise _error(error) from error
    return result


@router.post("/challenges/{challenge_id}/approve")
def approve_challenge(challenge_id: UUID, body: ApproveBody, request: Request, principal: MobilePrincipal = Depends(require_active_mobile_principal), session: Session = Depends(get_db)) -> dict[str, str]:
    try:
        signature = base64.b64decode(body.signature, validate=True)
        _service(request, session).approve(challenge_id, principal.device_id, signature, body.scan_nonce)
        session.commit()
    except (ValueError, WebLoginConflict) as error:
        session.rollback()
        if isinstance(error, ValueError):
            raise ApiError(422, "invalid_device_signature", "invalid device signature") from error
        raise _error(error) from error
    return {"status": "approved"}


@router.post("/challenges/{challenge_id}/exchange")
def exchange_challenge(challenge_id: UUID, body: ExchangeBody, request: Request, response: Response, session: Session = Depends(get_db)) -> dict[str, object]:
    try:
        result = _service(request, session).exchange(challenge_id, body.browser_proof)
        session.commit()
    except WebLoginConflict as error:
        session.rollback()
        raise _error(error) from error
    secure = bool(getattr(getattr(request.app.state, "settings", None), "web_cookie_secure", False))
    response.set_cookie("muyu_web_session", result.raw_cookie, httponly=True, secure=secure, samesite="lax", path="/", max_age=max(1, int((result.expires_at - datetime.now(timezone.utc)).total_seconds())))
    return {"status": "authenticated", "expires_at": result.expires_at.isoformat()}


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(response: Response, principal: WebPrincipal = Depends(require_web_principal), session: Session = Depends(get_db)) -> Response:
    stored = session.get(WebSession, principal.session_id)
    if stored is not None:
        stored.status = WebSessionStatus.REVOKED
        stored.revoked_at = datetime.now(timezone.utc)
        session.commit()
    response.delete_cookie("muyu_web_session", path="/")
    response.status_code = status.HTTP_204_NO_CONTENT
    return response


@router.get("/sessions")
def list_sessions(principal: WebPrincipal = Depends(require_web_principal), session: Session = Depends(get_db)) -> list[dict[str, object]]:
    rows = session.query(WebSession).filter(WebSession.user_id == principal.user_id).all()
    return [{"id": str(row.id), "status": row.status.value, "expires_at": row.expires_at.isoformat()} for row in rows]


@router.post("/sessions/{session_id}/revoke", status_code=status.HTTP_204_NO_CONTENT)
def revoke_session(session_id: UUID, principal: MobilePrincipal = Depends(require_active_mobile_principal), session: Session = Depends(get_db)) -> Response:
    row = session.get(WebSession, session_id)
    if row is None or row.user_id != principal.user_id:
        raise ApiError(403, "approval_not_allowed", "session revocation is not authorized")
    row.status = WebSessionStatus.REVOKED
    row.revoked_at = datetime.now(timezone.utc)
    session.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@sessions_router.get("")
def list_sessions_alias(principal: WebPrincipal = Depends(require_web_principal), session: Session = Depends(get_db)) -> list[dict[str, object]]:
    return list_sessions(principal, session)


@sessions_router.post("/{session_id}/revoke", status_code=status.HTTP_204_NO_CONTENT)
def revoke_session_alias(session_id: UUID, principal: MobilePrincipal = Depends(require_active_mobile_principal), session: Session = Depends(get_db)) -> Response:
    return revoke_session(session_id, principal, session)
