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
from app.task.service import TaskCreate, TaskNotFoundError, TaskPatch, TaskRuleError, TaskService


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


class DelayRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    new_due_at: datetime
    reason: str = Field(min_length=1, max_length=50)
    note: str | None = Field(default=None, max_length=2000)


class BlockRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    blocked_reason: str = Field(max_length=2000)
    resume_handler_id: UUID
    waiting_for_user_id: UUID | None = None


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
    blocked_reason: str | None
    blocked_since: datetime | None
    resume_handler_id: UUID | None
    waiting_for_user_id: UUID | None
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
    delay_count: int
    total_delay_minutes: int


class DelayRecordResponse(BaseModel):
    id: UUID
    task_id: UUID
    user_id: UUID
    original_due_at: datetime
    new_due_at: datetime
    delayed_at: datetime
    delay_duration_minutes: int
    reason: str
    note: str | None
    created_at: datetime


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
    service = TaskService(session)
    return [
        _task_response(task, service)
        for task in service.list_tasks(user_id, parent_task_id=parent_task_id)
    ]


@router.post("/api/tasks", response_model=TaskResponse, status_code=status.HTTP_201_CREATED)
def create_task(
    payload: TaskCreateRequest,
    request: Request,
    user_id: UUID = Depends(require_access_token),
    session: Session = Depends(get_db),
) -> TaskResponse:
    service = TaskService(session)
    try:
        task = service.create(
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
    return _task_response(task, service)


@router.get("/api/tasks/{task_id}", response_model=TaskResponse)
def get_task(task_id: UUID, session: Session = Depends(get_db), _user_id: UUID = Depends(require_access_token)) -> TaskResponse:
    service = TaskService(session)
    try:
        return _task_response(service.get(task_id), service)
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
    service = TaskService(session)
    try:
        task = service.update(
            task_id, user_id, TaskPatch(**fields), request_id=request.state.request_id
        )
    except (TaskNotFoundError, TaskRuleError) as error:
        _raise_task_error(error)
    return _task_response(task, service)


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
    service = TaskService(session)
    try:
        task = service.transfer(
            task_id, user_id, payload.new_handler_id, request_id=request.state.request_id
        )
    except (TaskNotFoundError, TaskRuleError) as error:
        _raise_task_error(error)
    return _task_response(task, service)


@router.post("/api/tasks/{task_id}/delay", response_model=TaskResponse)
def delay_task(
    task_id: UUID,
    payload: DelayRequest,
    request: Request,
    user_id: UUID = Depends(require_access_token),
    session: Session = Depends(get_db),
) -> TaskResponse:
    service = TaskService(session)
    try:
        task = service.delay(
            task_id,
            user_id,
            new_due_at=payload.new_due_at,
            reason=payload.reason,
            note=payload.note,
            request_id=request.state.request_id,
        )
    except (TaskNotFoundError, TaskRuleError) as error:
        _raise_task_error(error)
    return _task_response(task, service)


@router.get("/api/tasks/{task_id}/delays", response_model=list[DelayRecordResponse])
def list_task_delays(
    task_id: UUID,
    session: Session = Depends(get_db),
    _user_id: UUID = Depends(require_access_token),
) -> list[DelayRecordResponse]:
    try:
        return [
            DelayRecordResponse.model_validate(record, from_attributes=True)
            for record in TaskService(session).list_delays(task_id)
        ]
    except (TaskNotFoundError, TaskRuleError) as error:
        _raise_task_error(error)


@router.post("/api/tasks/{task_id}/block", response_model=TaskResponse)
def block_task(
    task_id: UUID,
    payload: BlockRequest,
    request: Request,
    user_id: UUID = Depends(require_access_token),
    session: Session = Depends(get_db),
) -> TaskResponse:
    service = TaskService(session)
    try:
        task = service.block(
            task_id,
            user_id,
            blocked_reason=payload.blocked_reason,
            resume_handler_id=payload.resume_handler_id,
            waiting_for_user_id=payload.waiting_for_user_id,
            request_id=request.state.request_id,
        )
    except (TaskNotFoundError, TaskRuleError) as error:
        _raise_task_error(error)
    return _task_response(task, service)


@router.post("/api/tasks/{task_id}/unblock", response_model=TaskResponse)
def unblock_task(
    task_id: UUID,
    request: Request,
    user_id: UUID = Depends(require_access_token),
    session: Session = Depends(get_db),
) -> TaskResponse:
    return _status_action(TaskService(session).unblock, task_id, user_id, request, session)


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
    return _task_response(task, TaskService(session))


def _task_response(task: Task, service: TaskService) -> TaskResponse:
    delay_count, total_delay_minutes = service.delay_summary(task.id)
    return TaskResponse(
        id=task.id,
        parent_task_id=task.parent_task_id,
        title=task.title,
        description=task.description,
        status=task.status,
        current_handler_id=task.current_handler_id,
        blocked_reason=task.blocked_reason,
        blocked_since=task.blocked_since,
        resume_handler_id=task.resume_handler_id,
        waiting_for_user_id=task.waiting_for_user_id,
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
        delay_count=delay_count,
        total_delay_minutes=total_delay_minutes,
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
