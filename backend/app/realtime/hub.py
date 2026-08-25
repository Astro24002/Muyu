from __future__ import annotations

import asyncio
from collections import defaultdict
from uuid import UUID


class WorkspaceHub:
    def __init__(self) -> None:
        self._subscribers: dict[UUID, set[asyncio.Queue[dict[str, object]]]] = defaultdict(set)

    async def subscribe(self, workspace_id: UUID) -> asyncio.Queue[dict[str, object]]:
        queue: asyncio.Queue[dict[str, object]] = asyncio.Queue(maxsize=32)
        self._subscribers[workspace_id].add(queue)
        return queue

    def unsubscribe(self, workspace_id: UUID, queue: asyncio.Queue[dict[str, object]]) -> None:
        self._subscribers[workspace_id].discard(queue)

    async def publish(self, workspace_id: UUID, cursor: int) -> None:
        message = {"type": "workspace.changed", "workspace_id": str(workspace_id), "cursor": cursor}
        for queue in tuple(self._subscribers.get(workspace_id, ())):
            try:
                queue.put_nowait(message)
            except asyncio.QueueFull:
                pass
