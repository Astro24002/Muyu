from __future__ import annotations

from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth.dependencies import MobilePrincipal, require_active_mobile_principal, require_mobile_principal
from app.db.enums import MembershipStatus
from app.db.models import WorkspaceInvite, WorkspaceMembership
from app.httpapi.dependencies import get_db
from app.httpapi.errors import ApiError
from app.workspaces.bootstrap_schemas import BootstrapPayload
from app.workspaces.bootstrap_service import WorkspaceBootstrapService
from app.workspaces.schemas import AcceptInviteBody, BindPartnerBody
from app.workspaces.service import WorkspaceConflict, WorkspaceService


class CreateWorkspaceBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: str | None = Field(default=None, max_length=160)


class InviteBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    phone: str = Field(min_length=1, max_length=40)


router = APIRouter(prefix="/api/v1", tags=["workspaces"])


def _error(error: WorkspaceConflict) -> ApiError:
    status_code = 409 if error.code in {"workspace_limit_reached", "approval_not_allowed", "lifecycle_conflict", "idempotency_key_reused", "partner_already_bound"} else 404 if error.code == "not_found" else 403 if error.code == "device_not_active" else 422
    return ApiError(status_code, error.code, str(error))


@router.post("/workspaces", status_code=status.HTTP_201_CREATED)
def create_workspace(
    body: CreateWorkspaceBody,
    principal: MobilePrincipal = Depends(require_active_mobile_principal),
    session: Session = Depends(get_db),
) -> dict[str, object]:
    try:
        workspace = WorkspaceService(session).create_workspace(principal.user_id, name=body.name)
        session.commit()
    except WorkspaceConflict as error:
        session.rollback()
        raise _error(error) from error
    return {"id": str(workspace.id), "name": workspace.name, "status": workspace.status.value}


@router.post("/workspaces/{workspace_id}/invites", status_code=status.HTTP_201_CREATED)
def create_invite(
    workspace_id: UUID,
    body: InviteBody,
    principal: MobilePrincipal = Depends(require_active_mobile_principal),
    session: Session = Depends(get_db),
) -> dict[str, object]:
    try:
        invite = WorkspaceService(session).create_invite(workspace_id, principal.user_id, body.phone)
        session.commit()
    except WorkspaceConflict as error:
        session.rollback()
        raise _error(error) from error
    return {"id": str(invite.id), "status": invite.status.value, "expires_at": invite.expires_at.isoformat()}


@router.post("/workspace-invites/{invite_id}/accept", response_model=BootstrapPayload, status_code=status.HTTP_200_OK)
def accept_invite(
    invite_id: UUID,
    body: AcceptInviteBody,
    principal: MobilePrincipal = Depends(require_mobile_principal),
    session: Session = Depends(get_db),
) -> BootstrapPayload:
    device_id = body.device_id or principal.device_id
    try:
        payload = WorkspaceBootstrapService(session).accept_invite(invite_id, principal.user_id, device_id, body.request_id)
        session.commit()
    except WorkspaceConflict as error:
        session.rollback()
        raise _error(error) from error
    return payload


@router.get("/workspaces/bootstrap", response_model=BootstrapPayload)
def workspace_bootstrap(
    principal: MobilePrincipal = Depends(require_mobile_principal),
    session: Session = Depends(get_db),
) -> BootstrapPayload:
    try:
        return WorkspaceBootstrapService(session).get_state(principal)
    except WorkspaceConflict as error:
        session.rollback()
        raise _error(error) from error


@router.post("/workspaces/bind-partner", response_model=BootstrapPayload, status_code=status.HTTP_201_CREATED)
def bind_partner(
    body: BindPartnerBody,
    principal: MobilePrincipal = Depends(require_active_mobile_principal),
    session: Session = Depends(get_db),
) -> BootstrapPayload:
    try:
        payload = WorkspaceBootstrapService(session).bind_partner(principal.user_id, body.phone, body.request_id)
        session.commit()
    except WorkspaceConflict as error:
        session.rollback()
        raise _error(error) from error
    return payload


@router.get("/workspaces/current")
def current_workspace(
    principal: MobilePrincipal = Depends(require_mobile_principal),
    session: Session = Depends(get_db),
) -> dict[str, object] | None:
    membership = session.scalar(select(WorkspaceMembership).where(WorkspaceMembership.user_id == principal.user_id, WorkspaceMembership.status == MembershipStatus.ACTIVE))
    if membership is None:
        return None
    from app.db.models import Workspace
    workspace = session.get(Workspace, membership.workspace_id)
    if workspace is None:
        return None
    members = session.scalars(select(WorkspaceMembership).where(WorkspaceMembership.workspace_id == membership.workspace_id, WorkspaceMembership.status == MembershipStatus.ACTIVE)).all()
    return {"id": str(workspace.id), "name": workspace.name, "status": workspace.status.value, "members": [{"user_id": str(item.user_id), "member_slot": item.member_slot} for item in members]}
