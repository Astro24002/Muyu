from __future__ import annotations

from datetime import datetime, timezone
from uuid import uuid4

import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.enums import MembershipStatus, TaskQuadrant
from app.db.models import Task, User, Workspace, WorkspaceCursor, WorkspaceMembership
from app.tasks.conflicts import TaskConflictError
from app.tasks.service import TaskService


def _workspace(session: Session) -> tuple[User, Workspace]:
    user = User(phone=f"+1555{uuid4().int % 10_000_000:07d}")
    workspace = Workspace(name="Labels")
    session.add_all([user, workspace])
    session.flush()
    session.add(
        WorkspaceMembership(
            workspace_id=workspace.id,
            user_id=user.id,
            member_slot=1,
            status=MembershipStatus.ACTIVE,
            joined_at=datetime.now(timezone.utc),
        )
    )
    session.add(WorkspaceCursor(workspace_id=workspace.id, next_cursor=1))
    session.flush()
    return user, workspace


def test_create_requires_a_quadrant_and_rejects_null_quadrants(db_engine) -> None:
    for quadrant in ("missing", None):
        with Session(db_engine) as session:
            user, workspace = _workspace(session)
            arguments = {
                "workspace_id": workspace.id,
                "actor_user_id": user.id,
                "request_id": uuid4(),
                "title": f"No quadrant: {quadrant}",
            }
            if quadrant != "missing":
                arguments["quadrant"] = quadrant

            with pytest.raises(TaskConflictError) as error:
                TaskService(session).create(**arguments)

            assert error.value.code == "invalid_request"
            assert session.scalar(select(Task).where(Task.workspace_id == workspace.id)) is None


def test_create_stores_a_required_quadrant_and_multiple_labels(db_engine) -> None:
    with Session(db_engine) as session:
        user, workspace = _workspace(session)
        task = TaskService(session).create(
            workspace.id,
            user.id,
            uuid4(),
            "Labelled task",
            quadrant="Q2",
            labels=["工作", "婚礼", "党员"],
        )

        assert task.quadrant == TaskQuadrant.Q2
        assert task.labels == ["工作", "婚礼", "党员"]
        assert TaskService(session).snapshot(task)["labels"] == ["工作", "婚礼", "党员"]


def test_create_deduplicates_trimmed_labels_case_insensitively_in_order(db_engine) -> None:
    with Session(db_engine) as session:
        user, workspace = _workspace(session)
        task = TaskService(session).create(
            workspace.id,
            user.id,
            uuid4(),
            "Normalized labels",
            quadrant="Q1",
            labels=[" 工作 ", "工作", " 婚礼 ", "婚礼", "党员"],
        )

        assert task.labels == ["工作", "婚礼", "党员"]


@pytest.mark.parametrize(
    ("case", "labels"),
    [
        ("empty label", [""]),
        ("whitespace-only label", ["   "]),
        ("too many labels", [f"label-{index}" for index in range(11)]),
        ("label too long", ["a" * 33]),
    ],
)
def test_create_rejects_invalid_labels_before_commit(db_engine, case: str, labels: list[str]) -> None:
    with Session(db_engine) as session:
        user, workspace = _workspace(session)

        with pytest.raises(TaskConflictError) as error:
            TaskService(session).create(
                workspace.id,
                user.id,
                uuid4(),
                f"Invalid labels: {case}",
                quadrant="Q3",
                labels=labels,
            )

        assert error.value.code == "invalid_request"
        assert session.scalar(select(Task).where(Task.workspace_id == workspace.id)) is None
