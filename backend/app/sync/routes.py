from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.httpapi.dependencies import get_db
from app.httpapi.errors import ApiError
from app.tasks.routes import Actor, require_actor
from app.sync.service import SyncCursorExpired, SyncService


router = APIRouter(prefix="/api/v1/workspaces/current", tags=["sync"])


@router.get("/snapshot")
def snapshot(actor: Actor = Depends(require_actor), session: Session = Depends(get_db)) -> dict[str, object]:
    try:
        return SyncService(session).snapshot(actor.workspace_id)
    except ValueError as error:
        raise ApiError(404, "workspace_access_denied", str(error)) from error


@router.get("/changes")
def changes(after_cursor: int = Query(ge=0), limit: int = Query(default=100, ge=1, le=500), actor: Actor = Depends(require_actor), session: Session = Depends(get_db)) -> dict[str, object]:
    try:
        return SyncService(session).changes(actor.workspace_id, after_cursor, limit)
    except SyncCursorExpired as error:
        raise ApiError(410, "sync_cursor_expired", str(error)) from error
