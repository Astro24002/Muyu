from __future__ import annotations

from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth.dependencies import MobilePrincipal, require_active_mobile_principal
from app.db.enums import MembershipStatus
from app.db.models import WorkspaceInvite, WorkspaceMembership
from app.httpapi.dependencies import get_db
from app.httpapi.errors import ApiError
from app.workspaces.service import WorkspaceConflict, WorkspaceService


class CreateWorkspaceBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: str | None = Field(default=None, max_length=160)


class InviteBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    phone: str = Field(min_length=1, max_length=40)


router = APIRouter(prefix="/api/v1", tags=["workspaces"])


def _error(error: WorkspaceConflict) -> ApiError:
    return ApiError(409 if error.code in {"workspace_limit_reached", "approval_not_allowed", "lifecycle_conflict"} else 422, error.code, str(error))


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


@router.post("/workspace-invites/{invite_id}/accept", status_code=status.HTTP_202_ACCEPTED)
def accept_invite(
    invite_id: UUID,
    body: dict[str, str],
    principal: MobilePrincipal = Depends(require_active_mobile_principal),
    session: Session = Depends(get_db),
) -> dict[str, object]:
    device_id = UUID(body.get("device_id", str(principal.device_id)))
    try:
        request, safety_code = WorkspaceService(session).accept_invite(invite_id, principal.user_id, device_id)
        session.commit()
    except (ValueError, WorkspaceConflict) as error:
        session.rollback()
        if isinstance(error, ValueError):
            raise ApiError(422, "invalid_request", "invalid device id") from error
        raise _error(error) from error
    return {"authorization_request_id": str(request.id), "status": request.status.value, "safety_code": safety_code, "expires_at": request.expires_at.isoformat()}


@router.get("/workspaces/current")
def current_workspace(
    principal: MobilePrincipal = Depends(require_active_mobile_principal),
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
