from __future__ import annotations

from typing import Any


class TaskConflictError(Exception):
    def __init__(
        self,
        code: str,
        message: str,
        conflict: object | None = None,
        *,
        conflict_snapshots: dict[str, dict[str, Any]] | None = None,
        conflict_details: list[dict[str, Any]] | None = None,
    ) -> None:
        super().__init__(message)
        self.code = code
        self.conflict = conflict
        self.conflict_snapshots = conflict_snapshots or {}
        self.conflict_details = conflict_details
