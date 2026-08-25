from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth.dependencies import MobilePrincipal, require_active_mobile_principal, require_mobile_principal
from app.httpapi.dependencies import get_db
from app.httpapi.errors import ApiError
from app.db.models import ActivityEvent, RecoveryRequest
from app.recovery.service import RecoveryConflict, RecoveryService


class RecoveryBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    workspace_id: UUID


class PhoneChangeBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    new_phone: str = Field(min_length=1, max_length=40)


router = APIRouter(prefix="/api/v1", tags=["recovery"])


def _error(error: RecoveryConflict) -> ApiError:
    return ApiError(409 if error.code in {"approval_not_allowed", "lifecycle_conflict"} else 422, error.code, str(error))


@router.post("/recovery/device-loss", status_code=status.HTTP_201_CREATED)
def start_recovery(body: RecoveryBody, principal: MobilePrincipal = Depends(require_mobile_principal), session: Session = Depends(get_db)) -> dict[str, object]:
    try:
        request = RecoveryService(session).start_device_loss(body.workspace_id, principal.user_id, principal.device_id)
        session.commit()
    except RecoveryConflict as error:
        session.rollback()
        raise _error(error) from error
    return {"id": str(request.id), "status": request.status.value, "expires_at": request.expires_at.isoformat()}


@router.post("/recovery/{request_id}/approve")
def approve_recovery(request_id: UUID, principal: MobilePrincipal = Depends(require_mobile_principal), session: Session = Depends(get_db)) -> dict[str, object]:
    try:
        request = RecoveryService(session).approve_device_loss(request_id, principal.user_id, principal.device_id)
        session.commit()
    except RecoveryConflict as error:
        session.rollback()
        raise _error(error) from error
    return {"id": str(request.id), "status": request.status.value}


@router.post("/recovery/{request_id}/begin-approval")
def begin_recovery_approval(request_id: UUID, principal: MobilePrincipal = Depends(require_mobile_principal), session: Session = Depends(get_db)) -> dict[str, object]:
    request = session.get(RecoveryRequest, request_id)
    if request is None or request.status.value != "PENDING":
        raise ApiError(410, "approval_challenge_expired", "recovery request is no longer pending")
    if request.requester_user_id == principal.user_id:
        raise ApiError(403, "approval_not_allowed", "recovery requires the other member")
    if request.workspace_id != principal.workspace_id:
        raise ApiError(403, "workspace_access_denied", "workspace access denied")
    return {"id": str(request.id), "status": request.status.value, "expires_at": request.expires_at.isoformat()}


@router.post("/account/phone-change", status_code=status.HTTP_201_CREATED)
def start_phone_change(body: PhoneChangeBody, principal: MobilePrincipal = Depends(require_active_mobile_principal), session: Session = Depends(get_db)) -> dict[str, object]:
    try:
        request = RecoveryService(session).start_phone_change(principal.user_id, body.new_phone)
        session.commit()
    except RecoveryConflict as error:
        session.rollback()
        raise _error(error) from error
    return {"id": str(request.id), "status": request.status.value, "expires_at": request.expires_at.isoformat()}


@router.post("/account/phone-change/{request_id}/approve")
def approve_phone_change(request_id: UUID, principal: MobilePrincipal = Depends(require_active_mobile_principal), session: Session = Depends(get_db)) -> dict[str, object]:
    try:
        request = RecoveryService(session).approve_phone_change(request_id, principal.user_id)
        session.commit()
    except RecoveryConflict as error:
        session.rollback()
        raise _error(error) from error
    return {"id": str(request.id), "status": request.status.value}


@router.get("/audit/security")
def security_audit(principal: MobilePrincipal = Depends(require_active_mobile_principal), session: Session = Depends(get_db)) -> list[dict[str, object]]:
    if principal.workspace_id is None:
        return []
    rows = session.scalars(
        select(ActivityEvent)
        .where(ActivityEvent.workspace_id == principal.workspace_id)
        .order_by(ActivityEvent.created_at.desc())
        .limit(100)
    ).all()
    return [
        {
            "id": str(row.id),
            "actor_user_id": str(row.actor_user_id),
            "event_type": row.event_type,
            "subject_id": row.payload.get("subject_id") if isinstance(row.payload, dict) else None,
            "created_at": row.created_at.isoformat(),
        }
        for row in rows
    ]
