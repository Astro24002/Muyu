from __future__ import annotations

from typing import Literal
from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Depends, Query, Request, status
from sqlalchemy.orm import Session

from app.db.models import Task
from app.httpapi.dependencies import get_db
from app.httpapi.errors import ApiError
from app.tasks.approval_schemas import (
    ApprovalActionRequest,
    ApprovalRejectRequest,
    ApprovalRequestCreate,
    approval_request_json,
    comment_json,
)
from app.tasks.approvals import TaskApprovalError, TaskApprovalResult, TaskApprovalService
from app.tasks.routes import Actor, _queue_hint, _require_workspace, require_actor, require_write_actor
from app.tasks.service import TaskService
from app.workspaces.classifications import ClassificationService


router = APIRouter(prefix="/api/v1/workspaces/{workspace_id}/approval-requests", tags=["task-approvals"])


def _approval_error(error: TaskApprovalError) -> ApiError:
    status_code = {
        "invalid_request": 422,
        "approval_not_found": 404,
        "approval_not_allowed": 403,
        "approval_conflicted": 409,
        "approval_already_resolved": 409,
        "approval_request_reused": 409,
        "classification_not_found": 422,
        "classification_exists": 409,
        "approval_already_pending": 409,
    }.get(error.code, 409)
    return ApiError(status_code, error.code, str(error))


def _result_json_with_service(result: TaskApprovalResult, service: TaskApprovalService) -> dict[str, object]:
    payload: dict[str, object] = {
        "approval_request": approval_request_json(result.request),
        "cursor": result.cursor,
    }
    if result.task is not None:
        payload["task"] = TaskService(service.session).snapshot(result.task)
    if result.comment is not None:
        payload["comment"] = comment_json(result.comment)
    if result.classification is not None:
        payload["classification"] = ClassificationService.json(result.classification)
    return payload


@router.post("", status_code=status.HTTP_201_CREATED)
def create_approval_request(
    workspace_id: UUID,
    body: ApprovalRequestCreate,
    request: Request,
    background_tasks: BackgroundTasks,
    actor: Actor = Depends(require_write_actor),
    session: Session = Depends(get_db),
) -> dict[str, object]:
    _require_workspace(actor, workspace_id)
    service = TaskApprovalService(session)
    try:
        approval = service.create(
            workspace_id,
            actor.user_id,
            body.request_id,
            body.task_id,
            body.request_type,
            body.proposed_changes,
            body.base_field_versions,
            body.comment_id,
        )
        session.commit()
    except TaskApprovalError as error:
        session.rollback()
        raise _approval_error(error) from error
    _queue_hint(background_tasks, request, workspace_id, service.last_cursor)
    return approval_request_json(approval) | {"cursor": service.last_cursor}


@router.get("")
def list_approval_requests(
    workspace_id: UUID,
    box: Literal["incoming", "outgoing"] | None = Query(default=None),
    actor: Actor = Depends(require_actor),
    session: Session = Depends(get_db),
) -> list[dict[str, object]]:
    _require_workspace(actor, workspace_id)
    try:
        rows = TaskApprovalService(session).list(workspace_id, actor.user_id, box)
    except TaskApprovalError as error:
        raise _approval_error(error) from error
    return [approval_request_json(row) for row in rows]


@router.post("/{approval_id}/approve")
def approve_approval_request(
    workspace_id: UUID,
    approval_id: UUID,
    body: ApprovalActionRequest,
    request: Request,
    background_tasks: BackgroundTasks,
    actor: Actor = Depends(require_write_actor),
    session: Session = Depends(get_db),
) -> dict[str, object]:
    _require_workspace(actor, workspace_id)
    service = TaskApprovalService(session)
    try:
        result = service.approve(workspace_id, actor.user_id, approval_id, body.request_id)
        session.commit()
    except TaskApprovalError as error:
        if error.code == "approval_conflicted":
            session.commit()
        else:
            session.rollback()
        raise _approval_error(error) from error
    _queue_hint(background_tasks, request, workspace_id, result.cursor)
    return _result_json_with_service(result, service)


@router.post("/{approval_id}/reject")
def reject_approval_request(
    workspace_id: UUID,
    approval_id: UUID,
    body: ApprovalRejectRequest,
    request: Request,
    background_tasks: BackgroundTasks,
    actor: Actor = Depends(require_write_actor),
    session: Session = Depends(get_db),
) -> dict[str, object]:
    _require_workspace(actor, workspace_id)
    service = TaskApprovalService(session)
    try:
        result = service.reject(workspace_id, actor.user_id, approval_id, body.request_id, body.reason)
        if isinstance(result, TaskApprovalResult):
            result_request = result.request
            result_cursor = result.cursor
            task_snapshot = (
                TaskService(session).snapshot(result.task)
                if result.task is not None
                else None
            )
        else:
            result_request = result
            result_cursor = result.resolved_cursor
            task_snapshot = None
            if result.task_id is not None:
                task = session.get(Task, result.task_id)
                if task is not None:
                    task_snapshot = TaskService(session).snapshot(task)
        session.commit()
    except TaskApprovalError as error:
        if error.code == "approval_conflicted":
            session.commit()
        else:
            session.rollback()
        raise _approval_error(error) from error
    _queue_hint(background_tasks, request, workspace_id, result_cursor)
    payload: dict[str, object] = {
        "approval_request": approval_request_json(result_request),
        "cursor": result_cursor,
    }
    if task_snapshot is not None:
        payload["task"] = task_snapshot
    return payload


@router.post("/{approval_id}/cancel")
def cancel_approval_request(
    workspace_id: UUID,
    approval_id: UUID,
    body: ApprovalActionRequest,
    request: Request,
    background_tasks: BackgroundTasks,
    actor: Actor = Depends(require_write_actor),
    session: Session = Depends(get_db),
) -> dict[str, object]:
    _require_workspace(actor, workspace_id)
    service = TaskApprovalService(session)
    try:
        result = service.cancel(workspace_id, actor.user_id, approval_id, body.request_id)
        session.commit()
    except TaskApprovalError as error:
        session.rollback()
        raise _approval_error(error) from error
    _queue_hint(background_tasks, request, workspace_id, result.resolved_cursor)
    return {"approval_request": approval_request_json(result), "cursor": result.resolved_cursor}


__all__ = ["router"]
