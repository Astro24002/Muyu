from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Depends, Request, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy.orm import Session

from app.httpapi.dependencies import get_db
from app.httpapi.errors import ApiError
from app.tasks.approval_schemas import approval_request_json
from app.tasks.approvals import TaskApprovalError, TaskApprovalService
from app.tasks.routes import Actor, _queue_hint, _require_workspace, require_actor, require_write_actor
from app.workspaces.classifications import ClassificationError, ClassificationService


class CreateClassificationRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    request_id: UUID
    name: str = Field(min_length=1, max_length=5)


router = APIRouter(prefix="/api/v1/workspaces", tags=["classifications"])


def _error(error: ClassificationError | TaskApprovalError) -> ApiError:
    code = getattr(error, "code", "invalid_request")
    status_code = {
        "invalid_request": 422,
        "classification_exists": 409,
        "classification_not_found": 422,
        "approval_not_found": 404,
        "approval_not_allowed": 403,
        "approval_request_reused": 409,
        "approval_already_pending": 409,
    }.get(code, 409)
    return ApiError(status_code, code, str(error))


def _list_for_workspace(workspace_id: UUID, actor: Actor, session: Session) -> list[dict[str, object]]:
    _require_workspace(actor, workspace_id)
    return [ClassificationService.json(row) for row in ClassificationService(session).list(workspace_id)]


@router.get("/current/classifications")
def list_current_classifications(
    actor: Actor = Depends(require_actor),
    session: Session = Depends(get_db),
) -> list[dict[str, object]]:
    """Return classifications for the workspace selected by the session."""

    return _list_for_workspace(actor.workspace_id, actor, session)


@router.get("/{workspace_id}/classifications")
def list_classifications(
    workspace_id: UUID,
    actor: Actor = Depends(require_actor),
    session: Session = Depends(get_db),
) -> list[dict[str, object]]:
    return _list_for_workspace(workspace_id, actor, session)


def _create_for_workspace(
    workspace_id: UUID,
    body: CreateClassificationRequest,
    request: Request,
    background_tasks: BackgroundTasks,
    actor: Actor,
    session: Session,
) -> dict[str, object]:
    _require_workspace(actor, workspace_id)
    service = TaskApprovalService(session)
    try:
        approval = service.create_classification(
            workspace_id,
            actor.user_id,
            body.request_id,
            body.name,
        )
        session.commit()
    except (ClassificationError, TaskApprovalError) as error:
        session.rollback()
        raise _error(error) from error
    _queue_hint(background_tasks, request, workspace_id, service.last_cursor)
    return {
        "pending": True,
        "approval_request": approval_request_json(approval),
        "cursor": service.last_cursor,
    }


@router.post("/current/classifications", status_code=status.HTTP_202_ACCEPTED)
def create_current_classification(
    body: CreateClassificationRequest,
    request: Request,
    background_tasks: BackgroundTasks,
    actor: Actor = Depends(require_write_actor),
    session: Session = Depends(get_db),
) -> dict[str, object]:
    return _create_for_workspace(
        actor.workspace_id,
        body,
        request,
        background_tasks,
        actor,
        session,
    )


@router.post("/{workspace_id}/classifications", status_code=status.HTTP_202_ACCEPTED)
def create_classification(
    workspace_id: UUID,
    body: CreateClassificationRequest,
    request: Request,
    background_tasks: BackgroundTasks,
    actor: Actor = Depends(require_write_actor),
    session: Session = Depends(get_db),
) -> dict[str, object]:
    return _create_for_workspace(
        workspace_id,
        body,
        request,
        background_tasks,
        actor,
        session,
    )


__all__ = ["router"]
