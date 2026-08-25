from __future__ import annotations

import asyncio
import hashlib
from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth.service import _hash_token
from app.db.enums import DeviceStatus, MembershipStatus, WebSessionStatus
from app.db.models import AndroidDevice, MobileSession, WebSession, WorkspaceMembership
from app.realtime.hub import WorkspaceHub


router = APIRouter(tags=["realtime"])


@router.websocket("/api/v1/realtime")
async def realtime(websocket: WebSocket) -> None:
    workspace_id_value = websocket.query_params.get("workspace_id")
    workspace_id: UUID | None = None
    if workspace_id_value:
        try:
            workspace_id = UUID(workspace_id_value)
        except ValueError:
            await websocket.close(code=1008)
            return
    if workspace_id is None:
        await websocket.close(code=1008)
        return
    engine = getattr(websocket.app.state, "engine", None)
    if engine is None or not _authorized(websocket, engine, workspace_id):
        await websocket.close(code=1008)
        return
    await websocket.accept()
    hub: WorkspaceHub = getattr(websocket.app.state, "workspace_hub", WorkspaceHub())
    queue = await hub.subscribe(workspace_id)
    try:
        while True:
            send_task = asyncio.create_task(queue.get())
            receive_task = asyncio.create_task(websocket.receive_text())
            done, pending = await asyncio.wait({send_task, receive_task}, return_when=asyncio.FIRST_COMPLETED)
            for task in pending:
                task.cancel()
            if send_task in done:
                await websocket.send_json(send_task.result())
            else:
                receive_task.result()
    except (WebSocketDisconnect, RuntimeError):
        pass
    finally:
        hub.unsubscribe(workspace_id, queue)


def _authorized(websocket: WebSocket, engine, workspace_id: UUID) -> bool:
    """Authenticate the socket before accepting it; tokens never appear in the URL."""
    with Session(engine) as session:
        authorization = websocket.headers.get("authorization", "")
        if authorization.lower().startswith("bearer "):
            stored = session.scalar(select(MobileSession).where(MobileSession.refresh_token_digest == _hash_token(authorization[7:].strip()), MobileSession.revoked_at.is_(None)))
            if stored is not None and stored.expires_at > datetime.now(timezone.utc):
                device = session.get(AndroidDevice, stored.device_id)
                membership = session.scalar(select(WorkspaceMembership.id).where(WorkspaceMembership.workspace_id == workspace_id, WorkspaceMembership.user_id == stored.user_id, WorkspaceMembership.status == MembershipStatus.ACTIVE))
                if device is not None and device.status == DeviceStatus.ACTIVE and membership is not None:
                    return True
        cookie = websocket.cookies.get("muyu_web_session")
        if cookie:
            stored_web = session.scalar(select(WebSession).where(WebSession.session_digest == hashlib.sha256(cookie.encode()).hexdigest(), WebSession.workspace_id == workspace_id, WebSession.status == WebSessionStatus.ACTIVE))
            if stored_web is not None and stored_web.expires_at > datetime.now(timezone.utc):
                return True
    return False
