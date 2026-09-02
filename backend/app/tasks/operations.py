from __future__ import annotations

import hashlib
import json
from copy import deepcopy
from typing import Any, Mapping
from uuid import UUID


def _wire_uuid(value: UUID | str | None) -> str | None:
    return str(value) if value is not None else None


def status_transition_payload(
    target_status: str,
    *,
    blocked_reason: str | None = None,
    resume_handler_id: UUID | str | None = None,
    waiting_for_user_id: UUID | str | None = None,
    review_rejection_reason: str | None = None,
) -> dict[str, Any]:
    """Return the complete, JSON-safe status mutation payload."""
    return {
        "target_status": target_status,
        "blocked_reason": blocked_reason,
        "resume_handler_id": _wire_uuid(resume_handler_id),
        "waiting_for_user_id": _wire_uuid(waiting_for_user_id),
        "review_rejection_reason": review_rejection_reason,
    }


def task_conflict_json(
    conflict: Any,
    current_snapshot: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    """Project a conflict without dropping status payload or version data."""
    status = getattr(conflict.status, "value", conflict.status)
    result: dict[str, Any] = {
        "id": str(conflict.id),
        "task_id": str(conflict.task_id),
        "field": conflict.target,
        "base": deepcopy(conflict.base_value),
        "current": deepcopy(conflict.current_value),
        "proposed": deepcopy(conflict.proposed_value),
        "status": status,
        "base_version": conflict.base_version,
        "current_version": conflict.current_version,
        "request_id": str(conflict.request_id),
        "created_at": conflict.created_at.isoformat() if conflict.created_at else None,
    }
    if conflict.target == "status":
        proposed_payload = conflict.proposed_value
        if not isinstance(proposed_payload, dict):
            proposed_payload = status_transition_payload(str(proposed_payload))
        result["proposed_payload"] = deepcopy(proposed_payload)
        result["base_status_version"] = conflict.base_version
        result["current_status_version"] = conflict.current_version
    if current_snapshot is not None:
        snapshot = deepcopy(dict(current_snapshot))
        result["current_snapshot"] = snapshot
        for field in (
            "reviewer_user_id",
            "review_submitted_at",
            "reviewed_at",
            "review_rejection_reason",
            "blocked_reason",
            "blocked_since",
            "resume_handler_id",
            "waiting_for_user_id",
            "field_versions",
            "status_version",
            "lifecycle_version",
        ):
            if field in snapshot:
                result[field] = snapshot[field]
    return result


def request_fingerprint(route: str, body: dict[str, Any]) -> str:
    encoded = json.dumps({"route": route, "body": body}, sort_keys=True, separators=(",", ":"), default=str)
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()
