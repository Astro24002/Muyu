from __future__ import annotations

from datetime import date
from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Depends, Query, Request, status
from sqlalchemy.orm import Session

from app.db.enums import AnniversaryKind, HabitFrequency, HabitStatus, LedgerEntryType
from app.httpapi.dependencies import get_db
from app.httpapi.errors import ApiError
from app.life.anniversaries import AnniversaryService
from app.life.checkins import HabitService
from app.life.common import LifeError, as_api_error, workspace_today
from app.life.ledger import LedgerService
from app.tasks.routes import Actor, _queue_hint, require_actor, require_write_actor

from .schemas import (
    AnniversaryCreateRequest,
    AnniversaryDeleteRequest,
    AnniversaryPatchRequest,
    GeneratePreparationRequest,
    HabitActionRequest,
    HabitCreateRequest,
    HabitDeleteRequest,
    HabitPatchRequest,
    LedgerCreateRequest,
    LedgerDeleteRequest,
    LedgerPatchRequest,
)


router = APIRouter(prefix="/api/v1", tags=["life"])


def _raise(error: LifeError) -> ApiError:
    return as_api_error(error)


def _ledger_json(entry, session: Session) -> dict[str, object]:
    value = LedgerService.snapshot(entry)
    from app.auth.profile import public_display_name
    from app.db.models import User

    user = session.get(User, entry.payer_or_payee_id)
    value["payer_or_payee_name"] = public_display_name(user) if user is not None else str(entry.payer_or_payee_id)
    return value


def _habit_json(service: HabitService, habit) -> dict[str, object]:
    return service.snapshot(habit, service.current_checkin(habit), include_history=True)


def _anniversary_json(service: AnniversaryService, row) -> dict[str, object]:
    return service.snapshot(row)


@router.get("/ledger")
@router.get("/workspaces/current/ledger", include_in_schema=False)
def list_ledger(
    month: str | None = Query(default=None),
    entry_type: LedgerEntryType | None = Query(default=None, alias="type"),
    category: str | None = Query(default=None),
    actor: Actor = Depends(require_actor),
    session: Session = Depends(get_db),
) -> dict[str, object]:
    try:
        service = LedgerService(session)
        rows = service.list(actor.workspace_id, month=month, entry_type=entry_type, category=category)
        return {"items": [_ledger_json(row, session) for row in rows], "month": month}
    except LifeError as error:
        raise _raise(error) from error


@router.get("/ledger/summary")
@router.get("/workspaces/current/ledger/summary", include_in_schema=False)
def ledger_summary(
    month: str | None = Query(default=None),
    actor: Actor = Depends(require_actor),
    session: Session = Depends(get_db),
) -> dict[str, object]:
    try:
        target_month = month or f"{workspace_today().year:04d}-{workspace_today().month:02d}"
        return LedgerService(session).summary(actor.workspace_id, target_month)
    except LifeError as error:
        raise _raise(error) from error


@router.post("/ledger", status_code=status.HTTP_201_CREATED)
@router.post("/workspaces/current/ledger", status_code=status.HTTP_201_CREATED, include_in_schema=False)
def create_ledger(
    body: LedgerCreateRequest,
    request: Request,
    background_tasks: BackgroundTasks,
    actor: Actor = Depends(require_write_actor),
    session: Session = Depends(get_db),
) -> dict[str, object]:
    try:
        service = LedgerService(session)
        entry = service.create(
            actor.workspace_id,
            actor.user_id,
            body.request_id,
            entry_type=body.type,
            amount=body.amount,
            amount_minor=body.amount_minor,
            title=body.title,
            category=body.category,
            payer_or_payee_id=body.payer_or_payee_id,
            entry_date=body.date,
            note=body.note,
        )
        session.commit()
        _queue_hint(background_tasks, request, actor.workspace_id, service.last_cursor)
        return _ledger_json(entry, session) | {"cursor": service.last_cursor}
    except LifeError as error:
        session.rollback()
        raise _raise(error) from error


@router.patch("/ledger/{entry_id}")
@router.patch("/workspaces/current/ledger/{entry_id}", include_in_schema=False)
def patch_ledger(
    entry_id: UUID,
    body: LedgerPatchRequest,
    request: Request,
    background_tasks: BackgroundTasks,
    actor: Actor = Depends(require_write_actor),
    session: Session = Depends(get_db),
) -> dict[str, object]:
    try:
        service = LedgerService(session)
        entry = service.patch(actor.workspace_id, actor.user_id, entry_id, body.request_id, body.expected_version, body.changes)
        session.commit()
        _queue_hint(background_tasks, request, actor.workspace_id, service.last_cursor)
        return _ledger_json(entry, session) | {"cursor": service.last_cursor}
    except LifeError as error:
        session.rollback()
        raise _raise(error) from error


@router.delete("/ledger/{entry_id}")
@router.delete("/workspaces/current/ledger/{entry_id}", include_in_schema=False)
def delete_ledger(
    entry_id: UUID,
    body: LedgerDeleteRequest,
    request: Request,
    background_tasks: BackgroundTasks,
    actor: Actor = Depends(require_write_actor),
    session: Session = Depends(get_db),
) -> dict[str, object]:
    try:
        service = LedgerService(session)
        entry = service.delete(actor.workspace_id, actor.user_id, entry_id, body.request_id, body.expected_version, body.confirm)
        session.commit()
        _queue_hint(background_tasks, request, actor.workspace_id, service.last_cursor)
        return _ledger_json(entry, session) | {"cursor": service.last_cursor}
    except LifeError as error:
        session.rollback()
        raise _raise(error) from error


@router.get("/habits")
@router.get("/workspaces/current/habits", include_in_schema=False)
def list_habits(
    owner: str = Query(default="mine"),
    actor: Actor = Depends(require_actor),
    session: Session = Depends(get_db),
) -> dict[str, object]:
    try:
        service = HabitService(session)
        return {"items": service.list(actor.workspace_id, actor.user_id, owner)}
    except LifeError as error:
        raise _raise(error) from error


@router.post("/habits", status_code=status.HTTP_201_CREATED)
@router.post("/workspaces/current/habits", status_code=status.HTTP_201_CREATED, include_in_schema=False)
def create_habit(
    body: HabitCreateRequest,
    request: Request,
    background_tasks: BackgroundTasks,
    actor: Actor = Depends(require_write_actor),
    session: Session = Depends(get_db),
) -> dict[str, object]:
    try:
        service = HabitService(session)
        habit = service.create(actor.workspace_id, actor.user_id, body.request_id, title=body.title, note=body.note, frequency=body.frequency, start_date=body.start_date)
        session.commit()
        _queue_hint(background_tasks, request, actor.workspace_id, service.last_cursor)
        return _habit_json(service, habit) | {"cursor": service.last_cursor}
    except LifeError as error:
        session.rollback()
        raise _raise(error) from error


@router.patch("/habits/{habit_id}")
@router.patch("/workspaces/current/habits/{habit_id}", include_in_schema=False)
def patch_habit(
    habit_id: UUID,
    body: HabitPatchRequest,
    request: Request,
    background_tasks: BackgroundTasks,
    actor: Actor = Depends(require_write_actor),
    session: Session = Depends(get_db),
) -> dict[str, object]:
    try:
        service = HabitService(session)
        habit = service.patch(actor.workspace_id, actor.user_id, habit_id, body.request_id, body.expected_version, body.changes)
        session.commit()
        _queue_hint(background_tasks, request, actor.workspace_id, service.last_cursor)
        return _habit_json(service, habit) | {"cursor": service.last_cursor}
    except LifeError as error:
        session.rollback()
        raise _raise(error) from error


def _habit_status_route(status_value: HabitStatus):
    def handler(
        habit_id: UUID,
        body: HabitActionRequest,
        request: Request,
        background_tasks: BackgroundTasks,
        actor: Actor = Depends(require_write_actor),
        session: Session = Depends(get_db),
    ) -> dict[str, object]:
        try:
            service = HabitService(session)
            habit = service.set_status(actor.workspace_id, actor.user_id, habit_id, body.request_id, body.expected_version, status_value)
            session.commit()
            _queue_hint(background_tasks, request, actor.workspace_id, service.last_cursor)
            return _habit_json(service, habit) | {"cursor": service.last_cursor}
        except LifeError as error:
            session.rollback()
            raise _raise(error) from error

    return handler


router.add_api_route("/habits/{habit_id}/pause", _habit_status_route(HabitStatus.PAUSED), methods=["POST"])
router.add_api_route("/habits/{habit_id}/resume", _habit_status_route(HabitStatus.ACTIVE), methods=["POST"])


@router.post("/habits/{habit_id}/checkin")
@router.post("/workspaces/current/habits/{habit_id}/checkin", include_in_schema=False)
def checkin_habit(
    habit_id: UUID,
    body: HabitActionRequest,
    request: Request,
    background_tasks: BackgroundTasks,
    actor: Actor = Depends(require_write_actor),
    session: Session = Depends(get_db),
) -> dict[str, object]:
    try:
        service = HabitService(session)
        habit, checkin = service.checkin(actor.workspace_id, actor.user_id, habit_id, body.request_id, body.expected_version)
        session.commit()
        _queue_hint(background_tasks, request, actor.workspace_id, service.last_cursor)
        return {"habit": _habit_json(service, habit), "checkin": service.checkin_snapshot(checkin), "cursor": service.last_cursor}
    except LifeError as error:
        session.rollback()
        raise _raise(error) from error


@router.post("/habits/{habit_id}/undo")
@router.post("/workspaces/current/habits/{habit_id}/undo", include_in_schema=False)
def undo_habit(
    habit_id: UUID,
    body: HabitActionRequest,
    request: Request,
    background_tasks: BackgroundTasks,
    actor: Actor = Depends(require_write_actor),
    session: Session = Depends(get_db),
) -> dict[str, object]:
    try:
        service = HabitService(session)
        habit = service.undo(actor.workspace_id, actor.user_id, habit_id, body.request_id, body.expected_version)
        session.commit()
        _queue_hint(background_tasks, request, actor.workspace_id, service.last_cursor)
        return _habit_json(service, habit) | {"cursor": service.last_cursor}
    except LifeError as error:
        session.rollback()
        raise _raise(error) from error


@router.delete("/habits/{habit_id}")
@router.delete("/workspaces/current/habits/{habit_id}", include_in_schema=False)
def delete_habit(
    habit_id: UUID,
    body: HabitDeleteRequest,
    request: Request,
    background_tasks: BackgroundTasks,
    actor: Actor = Depends(require_write_actor),
    session: Session = Depends(get_db),
) -> dict[str, object]:
    try:
        service = HabitService(session)
        habit = service.delete(actor.workspace_id, actor.user_id, habit_id, body.request_id, body.expected_version, body.confirm)
        session.commit()
        _queue_hint(background_tasks, request, actor.workspace_id, service.last_cursor)
        return _habit_json(service, habit) | {"cursor": service.last_cursor}
    except LifeError as error:
        session.rollback()
        raise _raise(error) from error


@router.get("/anniversaries")
@router.get("/workspaces/current/anniversaries", include_in_schema=False)
def list_anniversaries(actor: Actor = Depends(require_actor), session: Session = Depends(get_db)) -> dict[str, object]:
    try:
        service = AnniversaryService(session)
        return {"items": service.list(actor.workspace_id, actor.user_id)}
    except LifeError as error:
        raise _raise(error) from error


@router.post("/anniversaries", status_code=status.HTTP_201_CREATED)
@router.post("/workspaces/current/anniversaries", status_code=status.HTTP_201_CREATED, include_in_schema=False)
def create_anniversary(
    body: AnniversaryCreateRequest,
    request: Request,
    background_tasks: BackgroundTasks,
    actor: Actor = Depends(require_write_actor),
    session: Session = Depends(get_db),
) -> dict[str, object]:
    try:
        service = AnniversaryService(session)
        row = service.create(actor.workspace_id, actor.user_id, body.request_id, title=body.title, anchor_date=body.anchor_date, kind=body.kind, prepare_days=body.prepare_days, note=body.note)
        session.commit()
        _queue_hint(background_tasks, request, actor.workspace_id, service.last_cursor)
        return _anniversary_json(service, row) | {"cursor": service.last_cursor}
    except LifeError as error:
        session.rollback()
        raise _raise(error) from error


@router.patch("/anniversaries/{anniversary_id}")
@router.patch("/workspaces/current/anniversaries/{anniversary_id}", include_in_schema=False)
def patch_anniversary(
    anniversary_id: UUID,
    body: AnniversaryPatchRequest,
    request: Request,
    background_tasks: BackgroundTasks,
    actor: Actor = Depends(require_write_actor),
    session: Session = Depends(get_db),
) -> dict[str, object]:
    try:
        service = AnniversaryService(session)
        row = service.patch(actor.workspace_id, actor.user_id, anniversary_id, body.request_id, body.expected_version, body.changes)
        session.commit()
        _queue_hint(background_tasks, request, actor.workspace_id, service.last_cursor)
        return _anniversary_json(service, row) | {"cursor": service.last_cursor}
    except LifeError as error:
        session.rollback()
        raise _raise(error) from error


@router.delete("/anniversaries/{anniversary_id}")
@router.delete("/workspaces/current/anniversaries/{anniversary_id}", include_in_schema=False)
def delete_anniversary(
    anniversary_id: UUID,
    body: AnniversaryDeleteRequest,
    request: Request,
    background_tasks: BackgroundTasks,
    actor: Actor = Depends(require_write_actor),
    session: Session = Depends(get_db),
) -> dict[str, object]:
    try:
        service = AnniversaryService(session)
        row = service.delete(actor.workspace_id, actor.user_id, anniversary_id, body.request_id, body.expected_version, body.confirm)
        session.commit()
        _queue_hint(background_tasks, request, actor.workspace_id, service.last_cursor)
        return _anniversary_json(service, row) | {"cursor": service.last_cursor}
    except LifeError as error:
        session.rollback()
        raise _raise(error) from error


@router.post("/anniversaries/{anniversary_id}/prepare")
@router.post("/workspaces/current/anniversaries/{anniversary_id}/prepare", include_in_schema=False)
def generate_preparation(
    anniversary_id: UUID,
    body: GeneratePreparationRequest,
    request: Request,
    background_tasks: BackgroundTasks,
    actor: Actor = Depends(require_write_actor),
    session: Session = Depends(get_db),
) -> dict[str, object]:
    try:
        service = AnniversaryService(session)
        task = service.generate_preparation(actor.workspace_id, actor.user_id, anniversary_id, body.request_id)
        session.commit()
        _queue_hint(background_tasks, request, actor.workspace_id, service.last_cursor)
        return {"task": TaskServiceJson.snapshot(session, task), "cursor": service.last_cursor, "source_key": task.source_key}
    except LifeError as error:
        session.rollback()
        raise _raise(error) from error


class TaskServiceJson:
    @staticmethod
    def snapshot(session: Session, task) -> dict[str, object]:
        from app.tasks.service import TaskService

        return TaskService(session).snapshot(task)
