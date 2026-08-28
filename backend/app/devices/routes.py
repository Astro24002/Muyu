from __future__ import annotations

import base64
import hashlib
from datetime import datetime, timedelta, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, Response, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth.dependencies import MobilePrincipal, require_active_mobile_principal, require_mobile_principal
from app.db.enums import ApprovalStatus, DeviceStatus
from app.db.models import AndroidDevice, DeviceAuthorizationRequest
from app.devices.service import DeviceConflict, DeviceService, DeviceSummary
from app.devices.signatures import b64url, signed_action_payload
from app.httpapi.dependencies import get_db
from app.httpapi.errors import ApiError
from app.workspaces.service import WorkspaceConflict, WorkspaceService


class DeviceRequestBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    public_key: str = Field(min_length=1, max_length=4096)
    label: str | None = Field(default=None, max_length=120)


class SignatureBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    signature: str = Field(min_length=1, max_length=4096)


router = APIRouter(prefix="/api/v1/devices", tags=["devices"])
compat_router = APIRouter(prefix="/api/v1/device-authorization-requests", tags=["devices"])


def _error(error: Exception) -> ApiError:
    code = getattr(error, "code", "invalid_request")
    return ApiError(
        404 if code == "not_found" else 409
        if code in {"workspace_limit_reached", "approval_not_allowed", "lifecycle_conflict"}
        else 422,
        code,
        str(error),
    )


def _revoke_error(error: DeviceConflict) -> ApiError:
    status_code = {
        "not_found": 404,
        "approval_not_allowed": 403,
        "device_not_active": 403,
        "device_not_verified": 403,
        "device_already_revoked": 409,
        "lifecycle_conflict": 409,
    }.get(error.code, 422)
    return ApiError(status_code, error.code, str(error))


@router.get("", response_model=list[DeviceSummary])
def list_devices(
    principal: MobilePrincipal = Depends(require_mobile_principal),
    session: Session = Depends(get_db),
) -> list[DeviceSummary]:
    """Return the caller's registered devices for the Android "My" page.

    Public keys and fingerprints are deliberately excluded.  Device records
    remain long-lived on the server; a revoked record is kept visible so the
    user can distinguish it from an unrecognized device.
    """
    return DeviceService(session).list_for_user(principal.user_id, principal.device_id)


@router.post("/authorization-requests", status_code=status.HTTP_201_CREATED)
def create_authorization_request(
    body: DeviceRequestBody,
    principal: MobilePrincipal = Depends(require_mobile_principal),
    session: Session = Depends(get_db),
) -> dict[str, object]:
    try:
        key = base64.b64decode(body.public_key, validate=True)
        if not key:
            raise ValueError
    except (ValueError, TypeError):
        raise ApiError(422, "invalid_request", "invalid device public key") from None
    fingerprint = hashlib.sha256(key).hexdigest()
    device = session.get(AndroidDevice, principal.device_id)
    if device is not None and device.status == DeviceStatus.PENDING:
        if device.user_id != principal.user_id or device.fingerprint != fingerprint:
            raise ApiError(403, "approval_not_allowed", "pending device key does not match session")
        if body.label:
            device.label = body.label
    else:
        existing = session.scalar(
            select(AndroidDevice).where(
                AndroidDevice.user_id == principal.user_id,
                AndroidDevice.fingerprint == fingerprint,
                AndroidDevice.status != DeviceStatus.REVOKED,
            )
        )
        if existing is not None:
            raise ApiError(409, "lifecycle_conflict", "device is already enrolled or pending")
        device = AndroidDevice(
            user_id=principal.user_id,
            public_key_der=key,
            fingerprint=fingerprint,
            label=body.label,
            status=DeviceStatus.PENDING,
        )
        session.add(device)
        session.flush()
    workspace_id = principal.workspace_id
    if workspace_id is None:
        from app.db.enums import MembershipStatus
        from app.db.models import WorkspaceMembership

        workspace_id = session.scalar(select(WorkspaceMembership.workspace_id).where(WorkspaceMembership.user_id == principal.user_id, WorkspaceMembership.status == MembershipStatus.ACTIVE))
    if workspace_id is None:
        raise ApiError(409, "workspace_access_denied", "workspace membership required")
    # A pending request is visible to the other member; approval chooses the device.
    from app.db.models import DeviceAuthorizationRequest
    import secrets
    safety_code = f"{secrets.randbelow(1_000_000):06d}"
    request = DeviceAuthorizationRequest(
        workspace_id=workspace_id,
        candidate_device_id=device.id,
        status=ApprovalStatus.PENDING,
        safety_code_digest=hashlib.sha256(safety_code.encode()).hexdigest(),
        expires_at=datetime.now(timezone.utc) + timedelta(minutes=10),
    )
    session.add(request)
    session.commit()
    return {"id": str(request.id), "status": request.status.value, "safety_code": safety_code, "expires_at": request.expires_at.isoformat()}


@router.get("/authorization-requests")
def list_authorization_requests(
    principal: MobilePrincipal = Depends(require_active_mobile_principal),
    session: Session = Depends(get_db),
) -> list[dict[str, object]]:
    from app.db.enums import MembershipStatus
    from app.db.models import WorkspaceMembership

    workspace_id = session.scalar(select(WorkspaceMembership.workspace_id).where(WorkspaceMembership.user_id == principal.user_id, WorkspaceMembership.status == MembershipStatus.ACTIVE))
    if workspace_id is None:
        return []
    requests = session.scalars(select(DeviceAuthorizationRequest).where(DeviceAuthorizationRequest.workspace_id == workspace_id).order_by(DeviceAuthorizationRequest.created_at.desc())).all()
    return [{"id": str(item.id), "status": item.status.value, "expires_at": item.expires_at.isoformat()} for item in requests]


@router.post("/authorization-requests/{request_id}/begin-approval")
def begin_approval(
    request_id: UUID,
    principal: MobilePrincipal = Depends(require_active_mobile_principal),
    session: Session = Depends(get_db),
) -> dict[str, object]:
    try:
        challenge = WorkspaceService(session).begin_approval(request_id, principal.device_id)
        session.commit()
    except WorkspaceConflict as error:
        session.rollback()
        raise _error(error) from error
    return {
        "id": str(request_id),
        "status": "PENDING",
        "nonce": base64.urlsafe_b64encode(challenge.nonce).rstrip(b"=").decode("ascii"),
        "signature_payload": b64url(
            signed_action_payload(
                action="DEVICE_APPROVE",
                approval_id=request_id,
                actor_device_id=principal.device_id,
                workspace_id=principal.workspace_id,
                nonce=challenge.nonce,
                expires_at=challenge.expires_at,
            )
        ),
        "expires_at": challenge.expires_at.isoformat(),
    }


@router.post("/authorization-requests/{request_id}/approve", status_code=status.HTTP_200_OK)
def approve_request(
    request_id: UUID,
    body: SignatureBody,
    principal: MobilePrincipal = Depends(require_active_mobile_principal),
    session: Session = Depends(get_db),
) -> dict[str, object]:
    try:
        signature = base64.b64decode(body.signature, validate=True)
        request = WorkspaceService(session).approve(request_id, principal.device_id, signature)
        session.commit()
    except (ValueError, WorkspaceConflict) as error:
        session.rollback()
        if isinstance(error, ValueError):
            raise ApiError(422, "invalid_device_signature", "invalid device signature") from error
        raise _error(error) from error
    return {"id": str(request.id), "status": request.status.value}


@router.post("/{device_id}/revoke", response_model=DeviceSummary, status_code=status.HTTP_200_OK)
def revoke_device(
    device_id: UUID,
    principal: MobilePrincipal = Depends(require_active_mobile_principal),
    session: Session = Depends(get_db),
) -> dict[str, object]:
    try:
        device = DeviceService(session).revoke(device_id, principal.user_id, principal.device_id)
        session.commit()
    except DeviceConflict as error:
        session.rollback()
        raise _revoke_error(error) from error
    return device


# Keep the plan's resource-oriented paths as aliases while the Android
# client uses the grouped ``/devices`` paths.
compat_router.add_api_route("", list_authorization_requests, methods=["GET"])
compat_router.add_api_route("/{request_id}/begin-approval", begin_approval, methods=["POST"])
compat_router.add_api_route("/{request_id}/approve", approve_request, methods=["POST"])
