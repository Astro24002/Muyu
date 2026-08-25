from __future__ import annotations


class TaskConflictError(Exception):
    def __init__(self, code: str, message: str, conflict: object | None = None) -> None:
        super().__init__(message)
        self.code = code
        self.conflict = conflict

