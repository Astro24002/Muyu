from __future__ import annotations

from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends, Query, Request, Response, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy.orm import Session

from app.activity.models import ActivityEvent
from app.httpapi.dependencies import get_db, require_access_token
from app.httpapi.errors import ApiError
from app.task.models import Task
from app.task.service import TaskCreate, TaskNotFoundError, TaskPatch, TaskRuleError, TaskService, UNSET


class TaskCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: str = Field(min_length=1, max_length=200)
    description: str = Field(default="", max_length=5000)
    assignee_ids: list[UUID] = Field(min_length=1, max_length=2)
    current_handler_id: UUID | None = None
    parent_task_id: UUID | None = None
    planned_start_at: datetime | None = None
    due_at: datetime | None = None
    estimated_minutes: int | None = Field(default=None, gt=0)


class TaskPatchRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: str | None = Field(default=None, min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=5000)
    assignee_ids: list[UUID] | None = Field(default=None, min_length=1, max_length=2)
    planned_start_at: datetime | None = None
    due_at: datetime | None = None
    estimated_minutes: int | None = Field(default=None, gt=0)


class TransferRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    new_handler_id: UUID


class TaskOrderRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    task_ids: list[UUID]


class TaskOrderResponse(BaseModel):
    task_ids: list[UUID]


class TaskResponse(BaseModel):
    id: UUID
    parent_task_id: UUID | None
    title: str
    description: str
    status: str
    current_handler_id: UUID
    planned_start_at: datetime | None
    due_at: datetime | None
    estimated_minutes: int | None
    completed_at: datetime | None
    created_by: UUID
    version: int
    status_version: int
    created_at: datetime
    updated_at: datetime
    assignee_ids: list[UUID]


class ActivityEventResponse(BaseModel):
    id: UUID
    actor_user_id: UUID
    target_type: str
    target_id: UUID
    action: str
    before_json: dict | None
    after_json: dict | None
    payload_json: dict
    aggregate_version: int
    request_id: str | None
    created_at: datetime


router = APIRouter(tags=["task"])


@router.get("/api/tasks", response_model=list[TaskResponse])
def list_tasks(
    parent_task_id: UUID | None = Query(default=None),
    user_id: UUID = Depends(require_access_token),
    session: Session = Depends(get_db),
) -> list[TaskResponse]:
    return [_task_response(task) for task in TaskService(session).list_tasks(user_id, parent_task_id=parent_task_id)]


@router.post("/api/tasks", response_model=TaskResponse, status_code=status.HTTP_201_CREATED)
def create_task(
    payload: TaskCreateRequest,
    request: Request,
    user_id: UUID = Depends(require_access_token),
    session: Session = Depends(get_db),
) -> TaskResponse:
    try:
        task = TaskService(session).create(
            user_id,
            TaskCreate(
                title=payload.title,
                description=payload.description,
                assignee_ids=tuple(payload.assignee_ids),
                current_handler_id=payload.current_handler_id,
                parent_task_id=payload.parent_task_id,
                planned_start_at=payload.planned_start_at,
                due_at=payload.due_at,
                estimated_minutes=payload.estimated_minutes,
            ),
            request_id=request.state.request_id,
        )
    except (TaskNotFoundError, TaskRuleError) as error:
        _raise_task_error(error)
    return _task_response(task)


@router.get("/api/tasks/{task_id}", response_model=TaskResponse)
def get_task(task_id: UUID, session: Session = Depends(get_db), _user_id: UUID = Depends(require_access_token)) -> TaskResponse:
    try:
        return _task_response(TaskService(session).get(task_id))
    except (TaskNotFoundError, TaskRuleError) as error:
        _raise_task_error(error)


@router.patch("/api/tasks/{task_id}", response_model=TaskResponse)
def update_task(
    task_id: UUID,
    payload: TaskPatchRequest,
    request: Request,
    user_id: UUID = Depends(require_access_token),
    session: Session = Depends(get_db),
) -> TaskResponse:
    fields = {
        name: getattr(payload, name)
        for name in payload.model_fields_set
    }
    if "assignee_ids" in fields and fields["assignee_ids"] is not None:
        fields["assignee_ids"] = tuple(fields["assignee_ids"])
    try:
        task = TaskService(session).update(
            task_id, user_id, TaskPatch(**fields), request_id=request.state.request_id
        )
    except (TaskNotFoundError, TaskRuleError) as error:
        _raise_task_error(error)
    return _task_response(task)


@router.delete("/api/tasks/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_task(
    task_id: UUID,
    request: Request,
    user_id: UUID = Depends(require_access_token),
    session: Session = Depends(get_db),
) -> Response:
    try:
        TaskService(session).delete(task_id, user_id, request_id=request.state.request_id)
    except (TaskNotFoundError, TaskRuleError) as error:
        _raise_task_error(error)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/api/tasks/{task_id}/start", response_model=TaskResponse)
def start_task(task_id: UUID, request: Request, user_id: UUID = Depends(require_access_token), session: Session = Depends(get_db)) -> TaskResponse:
    return _status_action(TaskService(session).start, task_id, user_id, request, session)


@router.post("/api/tasks/{task_id}/complete", response_model=TaskResponse)
def complete_task(task_id: UUID, request: Request, user_id: UUID = Depends(require_access_token), session: Session = Depends(get_db)) -> TaskResponse:
    return _status_action(TaskService(session).complete, task_id, user_id, request, session)


@router.post("/api/tasks/{task_id}/reopen", response_model=TaskResponse)
def reopen_task(task_id: UUID, request: Request, user_id: UUID = Depends(require_access_token), session: Session = Depends(get_db)) -> TaskResponse:
    return _status_action(TaskService(session).reopen, task_id, user_id, request, session)


@router.post("/api/tasks/{task_id}/cancel", response_model=TaskResponse)
def cancel_task(task_id: UUID, request: Request, user_id: UUID = Depends(require_access_token), session: Session = Depends(get_db)) -> TaskResponse:
    return _status_action(TaskService(session).cancel, task_id, user_id, request, session)


@router.post("/api/tasks/{task_id}/transfer", response_model=TaskResponse)
def transfer_task(
    task_id: UUID,
    payload: TransferRequest,
    request: Request,
    user_id: UUID = Depends(require_access_token),
    session: Session = Depends(get_db),
) -> TaskResponse:
    try:
        task = TaskService(session).transfer(
            task_id, user_id, payload.new_handler_id, request_id=request.state.request_id
        )
    except (TaskNotFoundError, TaskRuleError) as error:
        _raise_task_error(error)
    return _task_response(task)


@router.get("/api/tasks/{task_id}/events", response_model=list[ActivityEventResponse])
def list_task_events(task_id: UUID, session: Session = Depends(get_db), _user_id: UUID = Depends(require_access_token)) -> list[ActivityEventResponse]:
    try:
        return [ActivityEventResponse.model_validate(event, from_attributes=True) for event in TaskService(session).list_events(task_id)]
    except (TaskNotFoundError, TaskRuleError) as error:
        _raise_task_error(error)


@router.get("/api/me/tasks/order", response_model=TaskOrderResponse)
def get_task_order(user_id: UUID = Depends(require_access_token), session: Session = Depends(get_db)) -> TaskOrderResponse:
    return TaskOrderResponse(task_ids=TaskService(session).get_order(user_id))


@router.put("/api/me/tasks/order", response_model=TaskOrderResponse)
def replace_task_order(
    payload: TaskOrderRequest,
    user_id: UUID = Depends(require_access_token),
    session: Session = Depends(get_db),
) -> TaskOrderResponse:
    try:
        task_ids = TaskService(session).replace_order(user_id, payload.task_ids)
    except TaskRuleError as error:
        _raise_task_error(error)
    return TaskOrderResponse(task_ids=task_ids)


def _status_action(method, task_id: UUID, user_id: UUID, request: Request, session: Session) -> TaskResponse:
    try:
        task = method(task_id, user_id, request_id=request.state.request_id)
    except (TaskNotFoundError, TaskRuleError) as error:
        _raise_task_error(error)
    return _task_response(task)


def _task_response(task: Task) -> TaskResponse:
    return TaskResponse(
        id=task.id,
        parent_task_id=task.parent_task_id,
        title=task.title,
        description=task.description,
        status=task.status,
        current_handler_id=task.current_handler_id,
        planned_start_at=task.planned_start_at,
        due_at=task.due_at,
        estimated_minutes=task.estimated_minutes,
        completed_at=task.completed_at,
        created_by=task.created_by,
        version=task.version,
        status_version=task.status_version,
        created_at=task.created_at,
        updated_at=task.updated_at,
        assignee_ids=[assignee.user_id for assignee in task.assignees],
    )


def _raise_task_error(error: TaskNotFoundError | TaskRuleError) -> None:
    if isinstance(error, TaskNotFoundError):
        raise ApiError(404, "TASK_NOT_FOUND", "task was not found") from error
    status_code = 409 if error.code in {
        "TASK_HAS_SUBTASKS",
        "SUBTASK_DEPTH_EXCEEDED",
        "INVALID_TASK_TRANSITION",
        "HANDLER_NOT_ASSIGNEE",
        "HANDLER_UNCHANGED",
        "DUPLICATE_TASK_ORDER",
        "INVALID_TASK_ORDER",
    } else 422
    raise ApiError(status_code, error.code, error.message) from error
