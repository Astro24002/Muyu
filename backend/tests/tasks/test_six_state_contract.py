from datetime import datetime, timezone
from types import SimpleNamespace
from uuid import uuid4

import pytest

from app.db.enums import TaskStatus
from app.tasks.service import TaskService


def canonical_statuses() -> set[str]:
    return {status.value for status in TaskStatus}


class _ScalarSession:
    def scalar(self, _query: object) -> int:
        return 0


def _task_with_status(status: str) -> SimpleNamespace:
    timestamp = datetime(2026, 9, 2, tzinfo=timezone.utc)
    return SimpleNamespace(
        id=uuid4(),
        workspace_id=uuid4(),
        parent_task_id=None,
        task_number="26090001",
        title="Contract task",
        description="",
        status=status,
        quadrant="Q1",
        labels=["工作"],
        progress=None,
        current_handler_id=uuid4(),
        blocked_reason=None,
        blocked_since=None,
        resume_handler_id=None,
        waiting_for_user_id=None,
        planned_start_at=None,
        due_at=None,
        estimated_minutes=None,
        completed_at=None,
        created_by=uuid4(),
        created_at=timestamp,
        updated_at=timestamp,
        version=1,
        field_versions={},
        lifecycle_version=1,
        status_version=1,
        deleted_at=None,
    )


def test_canonical_statuses_are_exactly_six() -> None:
    assert canonical_statuses() == {
        "TODO",
        "IN_PROGRESS",
        "BLOCKED",
        "REVIEW",
        "DONE",
        "CANCELLED",
    }


@pytest.mark.parametrize(
    ("legacy_status", "canonical_status"),
    [("WAITING", "BLOCKED"), ("COMPLETED", "DONE")],
)
def test_legacy_statuses_are_normalized_when_reading_snapshots(
    legacy_status: str,
    canonical_status: str,
) -> None:
    snapshot = TaskService(_ScalarSession()).snapshot(_task_with_status(legacy_status))

    assert snapshot["status"] == canonical_status
