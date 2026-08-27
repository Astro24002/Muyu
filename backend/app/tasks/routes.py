from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
from uuid import UUID, uuid4

from fastapi import APIRouter, BackgroundTasks, Depends, Request, Response, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth.service import _hash_token
from app.db.enums import ChangeAction, ConflictStatus, MembershipStatus, OperationType, Resolution, WebSessionStatus
from app.db.models import AndroidDevice, ImportantDate, MobileSession, Task, TaskConflict, TaskOperation, User, WebSession, WorkspaceChangeLog, WorkspaceMembership
from app.httpapi.dependencies import get_db
from app.httpapi.errors import ApiError
from app.tasks.comments import add_comment, list_comments
from app.tasks.conflicts import TaskConflictError
from app.tasks.delays import add_delay, list_delays
from app.tasks.recurrence import create_rule
from app.tasks.schemas import CommentRequest, CreateTaskRequest, DelayRequest, LifecycleRequest, PatchTaskRequest, ResolveConflictRequest, TransitionRequest
from app.tasks.search import search_tasks
from app.tasks.service import TaskService


@dataclass(frozen=True)
class Actor:
    user_id: UUID
    workspace_id: UUID
    device_id: UUID | None = None
    web_session_id: UUID | None = None


router = APIRouter(prefix="/api/v1", tags=["tasks"])


def _queue_hint(background_tasks: BackgroundTasks, request: Request, workspace_id: UUID, cursor: int | None) -> None:
    if cursor is None:
        return
    hub = getattr(request.app.state, "workspace_hub", None)
    if hub is not None:
        background_tasks.add_task(hub.publish, workspace_id, cursor)


def require_actor(request: Request, session: Session = Depends(get_db)) -> Actor:
    authorization = request.headers.get("authorization", "")
    if authorization.lower().startswith("bearer "):
        token = authorization[7:].strip()
        stored = session.scalar(select(MobileSession).where(MobileSession.refresh_token_digest == _hash_token(token), MobileSession.revoked_at.is_(None)))
        if stored is not None:
            device = session.get(AndroidDevice, stored.device_id)
            user = session.get(User, stored.user_id)
            if (
                device is not None
                and user is not None
                and device.status.value == "ACTIVE"
                and stored.expires_at > datetime.now(timezone.utc)
            ):
                workspace_id = _workspace_id(session, user.id)
                if workspace_id is not None:
                    return Actor(user.id, workspace_id, device.id)
    cookie = request.cookies.get("muyu_web_session")
    if cookie:
        digest = hashlib.sha256(cookie.encode()).hexdigest()
        stored_web = session.scalar(select(WebSession).where(WebSession.session_digest == digest, WebSession.status == WebSessionStatus.ACTIVE))
        if stored_web is not None and stored_web.expires_at > datetime.now(timezone.utc):
            return Actor(stored_web.user_id, stored_web.workspace_id, web_session_id=stored_web.id)
    raise ApiError(401, "authentication_required", "authentication required")


def _workspace_id(session: Session, user_id: UUID) -> UUID | None:
    return session.scalar(select(WorkspaceMembership.workspace_id).where(WorkspaceMembership.user_id == user_id, WorkspaceMembership.status == MembershipStatus.ACTIVE))


def _task_json(service: TaskService, task: Task) -> dict[str, object]:
    return service.snapshot(task)


def _task_error(error: TaskConflictError) -> ApiError:
    status_code = 409 if error.code in {"field_conflict", "lifecycle_conflict", "idempotency_key_reused"} else 422 if error.code in {"invalid_request", "nested_task_not_allowed"} else 404 if error.code == "not_found" else 409
    details = {}
    if isinstance(error.conflict, list):
        details["conflicts"] = [{"id": str(item.id), "field": item.target, "base": item.base_value, "current": item.current_value, "proposed": item.proposed_value} for item in error.conflict]
    return ApiError(status_code, error.code, str(error), details)


@router.post("/tasks", status_code=status.HTTP_201_CREATED)
def create_task(body: CreateTaskRequest, request: Request, background_tasks: BackgroundTasks, actor: Actor = Depends(require_actor), session: Session = Depends(get_db)) -> dict[str, object]:
    try:
        due_at = datetime.fromisoformat(body.due_at) if body.due_at else None
        service = TaskService(session)
        planned_start_at = datetime.fromisoformat(body.planned_start_at) if body.planned_start_at else None
        task = service.create(actor.workspace_id, actor.user_id, body.request_id, body.title, body.description, due_at, body.parent_task_id, body.assignee_ids, planned_start_at, body.estimated_minutes)
        session.commit()
    except (ValueError, TaskConflictError) as error:
        session.rollback()
        if isinstance(error, ValueError):
            raise ApiError(422, "invalid_request", "invalid due_at") from error
        raise _task_error(error) from error
    _queue_hint(background_tasks, request, actor.workspace_id, service.last_cursor)
    return _task_json(TaskService(session), task) | {"cursor": service.last_cursor}


@router.get("/tasks")
def list_tasks(actor: Actor = Depends(require_actor), session: Session = Depends(get_db)) -> list[dict[str, object]]:
    service = TaskService(session)
    tasks = session.scalars(select(Task).where(Task.workspace_id == actor.workspace_id, Task.deleted_at.is_(None)).order_by(Task.updated_at.desc())).all()
    return [_task_json(service, task) for task in tasks]


@router.get("/tasks/search")
def search_task_route(q: str, actor: Actor = Depends(require_actor), session: Session = Depends(get_db)) -> list[dict[str, object]]:
    service = TaskService(session)
    return [_task_json(service, task) for task in search_tasks(session, actor.workspace_id, q)]


@router.get("/tasks/{task_id}")
def get_task(task_id: UUID, actor: Actor = Depends(require_actor), session: Session = Depends(get_db)) -> dict[str, object]:
    task = session.scalar(select(Task).where(Task.id == task_id, Task.workspace_id == actor.workspace_id))
    if task is None:
        raise ApiError(404, "not_found", "task not found")
    return _task_json(TaskService(session), task)


@router.patch("/tasks/{task_id}")
def patch_task(task_id: UUID, body: PatchTaskRequest, request: Request, background_tasks: BackgroundTasks, actor: Actor = Depends(require_actor), session: Session = Depends(get_db)) -> dict[str, object]:
    try:
        service = TaskService(session)
        task = service.patch(actor.workspace_id, actor.user_id, task_id, body.request_id, body.changes, body.base_field_versions)
        session.commit()
    except TaskConflictError as error:
        session.commit() if error.code == "field_conflict" else session.rollback()
        raise _task_error(error) from error
    _queue_hint(background_tasks, request, actor.workspace_id, service.last_cursor)
    return _task_json(TaskService(session), task) | {"cursor": service.last_cursor}


@router.post("/tasks/{task_id}/lifecycle")
def lifecycle_task(task_id: UUID, body: LifecycleRequest, request: Request, background_tasks: BackgroundTasks, actor: Actor = Depends(require_actor), session: Session = Depends(get_db)) -> dict[str, object]:
    try:
        service = TaskService(session)
        task = service.lifecycle(actor.workspace_id, actor.user_id, task_id, body.request_id, body.action, body.base_lifecycle_version)
        session.commit()
    except TaskConflictError as error:
        session.rollback()
        raise _task_error(error) from error
    _queue_hint(background_tasks, request, actor.workspace_id, service.last_cursor)
    return _task_json(TaskService(session), task) | {"cursor": service.last_cursor}


@router.post("/tasks/{task_id}/transition")
def transition_task(task_id: UUID, body: TransitionRequest, request: Request, background_tasks: BackgroundTasks, actor: Actor = Depends(require_actor), session: Session = Depends(get_db)) -> dict[str, object]:
    try:
        service = TaskService(session)
        task = service.transition(actor.workspace_id, actor.user_id, task_id, body.request_id, body.target_status, body.base_status_version, body.blocked_reason, body.resume_handler_id, body.waiting_for_user_id)
        session.commit()
    except TaskConflictError as error:
        if error.code == "field_conflict":
            session.commit()
        else:
            session.rollback()
        raise _task_error(error) from error
    _queue_hint(background_tasks, request, actor.workspace_id, service.last_cursor)
    return _task_json(TaskService(session), task) | {"cursor": service.last_cursor}


@router.post("/tasks/{task_id}/restore")
def restore_task(task_id: UUID, body: LifecycleRequest, request: Request, background_tasks: BackgroundTasks, actor: Actor = Depends(require_actor), session: Session = Depends(get_db)) -> dict[str, object]:
    try:
        service = TaskService(session)
        task = service.restore(actor.workspace_id, actor.user_id, task_id, body.request_id, body.base_lifecycle_version)
        session.commit()
    except TaskConflictError as error:
        session.rollback()
        raise _task_error(error) from error
    _queue_hint(background_tasks, request, actor.workspace_id, service.last_cursor)
    return _task_json(TaskService(session), task) | {"cursor": service.last_cursor}


@router.get("/tasks/{task_id}/conflicts")
def conflicts(task_id: UUID, actor: Actor = Depends(require_actor), session: Session = Depends(get_db)) -> list[dict[str, object]]:
    rows = session.scalars(select(TaskConflict).where(TaskConflict.workspace_id == actor.workspace_id, TaskConflict.task_id == task_id).order_by(TaskConflict.created_at.desc())).all()
    return [{"id": str(row.id), "field": row.target, "base": row.base_value, "current": row.current_value, "proposed": row.proposed_value, "status": row.status.value} for row in rows]


@router.post("/tasks/{task_id}/conflicts/{conflict_id}/resolve")
def resolve_conflict(task_id: UUID, conflict_id: UUID, body: ResolveConflictRequest, request: Request, background_tasks: BackgroundTasks, actor: Actor = Depends(require_actor), session: Session = Depends(get_db)) -> dict[str, object]:
    try:
        service = TaskService(session)
        task = service.resolve_conflict(actor.workspace_id, actor.user_id, task_id, conflict_id, body.request_id, body.resolution)
        session.commit()
    except TaskConflictError as error:
        session.rollback()
        raise _task_error(error) from error
    _queue_hint(background_tasks, request, actor.workspace_id, service.last_cursor)
    return _task_json(service, task) | {"cursor": service.last_cursor}


@router.post("/tasks/{task_id}/comments", status_code=status.HTTP_201_CREATED)
def comment_task(task_id: UUID, body: CommentRequest, request: Request, background_tasks: BackgroundTasks, actor: Actor = Depends(require_actor), session: Session = Depends(get_db)) -> dict[str, object]:
    try:
        comment = add_comment(session, actor.workspace_id, actor.user_id, task_id, body.body, body.request_id)
        cursor = session.scalar(select(WorkspaceChangeLog.cursor).where(WorkspaceChangeLog.operation_id == body.request_id))
        session.commit()
    except TaskConflictError as error:
        session.rollback()
        raise _task_error(error) from error
    _queue_hint(background_tasks, request, actor.workspace_id, cursor)
    return {"id": str(comment.id), "task_id": str(comment.task_id), "body": comment.body, "created_at": comment.created_at.isoformat(), "cursor": cursor}


@router.get("/tasks/{task_id}/comments")
def comments(task_id: UUID, actor: Actor = Depends(require_actor), session: Session = Depends(get_db)) -> list[dict[str, object]]:
    if session.scalar(select(Task.id).where(Task.id == task_id, Task.workspace_id == actor.workspace_id)) is None:
        raise ApiError(404, "not_found", "task not found")
    return [{"id": str(item.id), "body": item.body, "author_user_id": str(item.author_user_id), "created_at": item.created_at.isoformat()} for item in list_comments(session, actor.workspace_id, task_id)]


@router.post("/tasks/{task_id}/delays", status_code=status.HTTP_201_CREATED)
def delay_task(task_id: UUID, body: DelayRequest, request: Request, background_tasks: BackgroundTasks, actor: Actor = Depends(require_actor), session: Session = Depends(get_db)) -> dict[str, object]:
    try:
        row = add_delay(session, actor.workspace_id, actor.user_id, task_id, datetime.fromisoformat(body.new_due_at), body.reason, body.note, body.request_id)
        cursor = session.scalar(select(WorkspaceChangeLog.cursor).where(WorkspaceChangeLog.operation_id == body.request_id))
        session.commit()
    except (ValueError, TaskConflictError) as error:
        session.rollback()
        if isinstance(error, ValueError):
            raise ApiError(422, "invalid_request", "invalid new_due_at") from error
        raise _task_error(error) from error
    _queue_hint(background_tasks, request, actor.workspace_id, cursor)
    return {
        "id": str(row.id), "task_id": str(row.task_id), "actor_user_id": str(row.actor_user_id),
        "original_due_at": row.original_due_at.isoformat(), "new_due_at": row.new_due_at.isoformat(),
        "delayed_at": row.delayed_at.isoformat(), "delay_duration_minutes": row.delay_duration_minutes,
        "reason": row.reason, "note": row.note, "created_at": row.created_at.isoformat(), "cursor": cursor,
    }


@router.get("/tasks/{task_id}/delays")
def delays(task_id: UUID, actor: Actor = Depends(require_actor), session: Session = Depends(get_db)) -> list[dict[str, object]]:
    if session.scalar(select(Task.id).where(Task.id == task_id, Task.workspace_id == actor.workspace_id)) is None:
        raise ApiError(404, "not_found", "task not found")
    return [{
        "id": str(item.id), "task_id": str(item.task_id), "actor_user_id": str(item.actor_user_id),
        "original_due_at": item.original_due_at.isoformat(), "new_due_at": item.new_due_at.isoformat(),
        "delayed_at": item.delayed_at.isoformat(), "delay_duration_minutes": item.delay_duration_minutes,
        "reason": item.reason, "note": item.note, "created_at": item.created_at.isoformat(),
    } for item in list_delays(session, actor.workspace_id, task_id)]


@router.get("/tasks/{task_id}/activity")
def activity(task_id: UUID, actor: Actor = Depends(require_actor), session: Session = Depends(get_db)) -> list[dict[str, object]]:
    task = session.scalar(select(Task).where(Task.id == task_id, Task.workspace_id == actor.workspace_id))
    if task is None:
        raise ApiError(404, "not_found", "task not found")
    operations = session.scalars(select(TaskOperation).where(TaskOperation.task_id == task_id).order_by(TaskOperation.created_at.asc())).all()
    comments_rows = list_comments(session, actor.workspace_id, task_id)
    delays_rows = list_delays(session, actor.workspace_id, task_id)
    events = [{"kind": "operation", "id": str(row.id), "operation_type": row.operation_type.value, "created_at": row.created_at.isoformat(), "request_id": str(row.request_id)} for row in operations]
    events += [{"kind": "comment", "id": str(row.id), "body": row.body, "author_user_id": str(row.author_user_id), "created_at": row.created_at.isoformat()} for row in comments_rows]
    events += [{"kind": "delay", "id": str(row.id), "actor_user_id": str(row.actor_user_id), "reason": row.reason, "note": row.note, "new_due_at": row.new_due_at.isoformat(), "delay_duration_minutes": row.delay_duration_minutes, "created_at": row.created_at.isoformat()} for row in delays_rows]
    return sorted(events, key=lambda item: (item["created_at"], item["id"]))


@router.post("/tasks/{task_id}/recurrence", status_code=status.HTTP_201_CREATED)
def recurrence(task_id: UUID, body: dict[str, str], actor: Actor = Depends(require_actor), session: Session = Depends(get_db)) -> dict[str, object]:
    try:
        request_id = __import__("uuid").UUID(body["request_id"]) if body.get("request_id") else __import__("uuid").uuid4()
        row = create_rule(session, actor.workspace_id, actor.user_id, task_id, body.get("rule", ""), request_id)
        session.commit()
    except ValueError as error:
        session.rollback()
        raise ApiError(422, "invalid_request", str(error)) from error
    return {"id": str(row.id), "rule": row.rule, "next_run_at": row.next_run_at.isoformat() if row.next_run_at else None, "cursor": session.scalar(select(WorkspaceChangeLog.cursor).where(WorkspaceChangeLog.operation_id == request_id))}


@router.post("/tasks/{task_id}/important-date", status_code=status.HTTP_201_CREATED)
def important_date(task_id: UUID, body: dict[str, str], actor: Actor = Depends(require_actor), session: Session = Depends(get_db)) -> dict[str, object]:
    try:
        request_id = UUID(body["request_id"])
        starts_at = datetime.fromisoformat(body["starts_at"])
        ends_at = datetime.fromisoformat(body["ends_at"]) if body.get("ends_at") else None
    except (KeyError, TypeError, ValueError) as error:
        raise ApiError(422, "invalid_request", "request_id, starts_at, and label are required") from error
    if not body.get("label"):
        raise ApiError(422, "invalid_request", "label is required")
    task = session.scalar(select(Task).where(Task.id == task_id, Task.workspace_id == actor.workspace_id))
    if task is None:
        raise ApiError(404, "not_found", "task not found")
    row = ImportantDate(workspace_id=actor.workspace_id, task_id=task_id, label=body["label"], starts_at=starts_at, ends_at=ends_at, created_by=actor.user_id)
    session.add(row)
    session.flush()
    service = TaskService(session)
    cursor = service._cursor(actor.workspace_id, task, ChangeAction.UPDATED, request_id)
    service._operation(actor.workspace_id, actor.user_id, request_id, task, OperationType.UPDATED, service.snapshot(task), service.snapshot(task), cursor)
    session.commit()
    return {"id": str(row.id), "task_id": str(task_id), "label": row.label, "starts_at": row.starts_at.isoformat(), "ends_at": row.ends_at.isoformat() if row.ends_at else None, "cursor": cursor}
