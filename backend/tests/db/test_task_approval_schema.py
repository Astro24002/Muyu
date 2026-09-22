from __future__ import annotations

from uuid import uuid4

import pytest
from sqlalchemy import inspect, text
from sqlalchemy.exc import DataError, IntegrityError
from sqlalchemy.orm import Session


def _user(session: Session, phone: str | None = None):
    from app.db.models import User

    user = User(phone=phone or f"+1555{uuid4().int % 10_000_000:07d}")
    session.add(user)
    session.flush()
    return user


def _workspace(session: Session):
    from app.db.models import Workspace

    workspace = Workspace()
    session.add(workspace)
    session.flush()
    return workspace


def _task(session: Session, workspace, user):
    from app.db.models import Task
    from tests.classification_fixtures import seed_approved_classification

    seed_approved_classification(session, workspace.id, user.id)
    task = Task(workspace_id=workspace.id, task_number="26080001", title="Schema task", quadrant="Q1", labels=["工作"], created_by=user.id)
    session.add(task)
    session.flush()
    return task


def test_task_approval_tables_columns_and_enum_values(db_engine) -> None:
    inspector = inspect(db_engine)
    assert {
        "task_number_sequences",
        "task_approval_requests",
        "workspace_classifications",
    }.issubset(inspector.get_table_names())

    task_columns = {column["name"] for column in inspector.get_columns("tasks")}
    assert {"task_number", "quadrant", "progress", "version", "field_versions", "status_version"} <= task_columns

    comment_columns = {column["name"] for column in inspector.get_columns("task_comments")}
    assert {"version", "deleted_at", "deleted_by"} <= comment_columns

    sequence_columns = {column["name"] for column in inspector.get_columns("task_number_sequences")}
    assert sequence_columns == {"period", "next_value"}

    approval_columns = {column["name"] for column in inspector.get_columns("task_approval_requests")}
    assert {
        "id",
        "workspace_id",
        "task_id",
        "comment_id",
        "requester_id",
        "approver_id",
        "request_type",
        "proposed_changes",
        "base_field_versions",
        "request_id",
        "created_at",
        "reviewed_at",
        "reviewed_by",
        "status",
        "rejection_reason",
        "resolved_cursor",
    } <= approval_columns

    from app.db.enums import PUBLIC_TASK_STATUS, TaskStatus

    assert TaskStatus.DONE.value == "DONE"
    assert PUBLIC_TASK_STATUS[TaskStatus.DONE] == "DONE"

    with Session(db_engine) as session:
        rows = session.execute(
            text(
                "SELECT t.typname, array_agg(e.enumlabel ORDER BY e.enumsortorder) "
                "FROM pg_type t JOIN pg_enum e ON e.enumtypid = t.oid "
                "JOIN pg_namespace n ON n.oid = t.typnamespace "
                "WHERE n.nspname = current_schema() AND t.typname IN "
                "('task_status', 'task_quadrant', 'task_approval_request_type', 'task_approval_request_status') "
                "GROUP BY t.typname"
            )
        ).all()
    assert dict(rows) == {
        "task_approval_request_status": ["PENDING", "APPROVED", "REJECTED", "CONFLICTED", "CANCELLED"],
        "task_approval_request_type": [
            "TASK_UPDATE",
            "QUADRANT_UPDATE",
            "STATUS_UPDATE",
            "TASK_DELETE",
            "TASK_RESTORE",
            "COMMENT_DELETE",
            "HANDLER_TRANSFER",
            "CLASSIFICATION_CREATE",
            "TASK_INVITATION",
        ],
        "task_quadrant": ["Q1", "Q2", "Q3", "Q4"],
        "task_status": ["TODO", "IN_PROGRESS", "BLOCKED", "REVIEW", "DONE", "CANCELLED"],
    }


def test_task_approval_indexes_constraints_and_progress_check(db_engine) -> None:
    inspector = inspect(db_engine)
    indexes = {
        index["name"]: tuple(index["column_names"])
        for index in inspector.get_indexes("task_approval_requests")
    }
    assert {
        "ix_task_approval_requests_workspace_status_approver": ("workspace_id", "status", "approver_id"),
        "ix_task_approval_requests_workspace_status_requester": ("workspace_id", "status", "requester_id"),
        "ix_task_approval_requests_task_status": ("task_id", "status"),
        "ix_task_approval_requests_comment_status": ("comment_id", "status"),
    }.items() <= indexes.items()

    task_unique_indexes = {
        index["name"]
        for index in inspector.get_indexes("tasks")
        if index.get("unique")
    }
    task_unique_constraints = {item["name"] for item in inspector.get_unique_constraints("tasks")}
    assert "uq_tasks_task_number" in task_unique_indexes | task_unique_constraints

    constraints = {item["name"] for item in inspector.get_check_constraints("tasks")}
    assert "ck_tasks_progress_allowed" in constraints
    approval_constraints = {item["name"] for item in inspector.get_check_constraints("task_approval_requests")}
    assert "ck_task_approval_requester_approver_distinct" in approval_constraints

    foreign_keys = {
        item["name"]: (item["referred_table"], item["options"].get("ondelete"))
        for item in inspector.get_foreign_keys("task_approval_requests")
    }
    assert foreign_keys["fk_task_approval_requests_workspace_id"][1] == "CASCADE"
    assert foreign_keys["fk_task_approval_requests_task_id"][1] == "RESTRICT"
    assert foreign_keys["fk_task_approval_requests_requester_id"][1] == "RESTRICT"
    assert foreign_keys["fk_task_approval_requests_approver_id"][1] == "RESTRICT"
    assert foreign_keys["fk_task_approval_requests_reviewed_by"][1] == "RESTRICT"


def test_task_approval_rejects_self_approval_and_invalid_progress(db_engine) -> None:
    with Session(db_engine) as session:
        user = _user(session)
        workspace = _workspace(session)
        task = _task(session, workspace, user)
        common = {
            "workspace_id": workspace.id,
            "task_id": task.id,
            "requester_id": user.id,
            "approver_id": user.id,
            "request_type": "TASK_UPDATE",
            "proposed_changes": {},
            "base_field_versions": {},
            "request_id": uuid4(),
        }
        with pytest.raises(IntegrityError):
            with session.begin_nested():
                session.execute(
                    text(
                        "INSERT INTO task_approval_requests "
                        "(id, workspace_id, task_id, requester_id, approver_id, request_type, proposed_changes, "
                        "base_field_versions, request_id, status) "
                        "VALUES (:id, :workspace_id, :task_id, :requester_id, :approver_id, :request_type, "
                        "CAST(:proposed_changes AS jsonb), CAST(:base_field_versions AS jsonb), :request_id, 'PENDING')"
                    ),
                    {**common, "id": uuid4(), "proposed_changes": "{}", "base_field_versions": "{}"},
                )

        for progress in (0, 10, 30, 100):
            with pytest.raises(IntegrityError):
                with session.begin_nested():
                    session.execute(
                        text("UPDATE tasks SET progress = :progress WHERE id = :task_id"),
                        {"progress": progress, "task_id": task.id},
                    )

        for progress in (None, 20, 40, 60, 80):
            session.execute(
                text("UPDATE tasks SET progress = :progress WHERE id = :task_id"),
                {"progress": progress, "task_id": task.id},
            )


def test_task_approval_request_type_rejects_removed_assignee_label(db_engine) -> None:
    with Session(db_engine) as session:
        with pytest.raises(DataError):
            with session.begin_nested():
                session.execute(text("SELECT 'ASSIGNEE_UPDATE'::task_approval_request_type"))


def test_task_approval_request_id_is_unique_within_workspace(db_engine) -> None:
    with Session(db_engine) as session:
        requester = _user(session)
        approver = _user(session)
        workspace = _workspace(session)
        task = _task(session, workspace, requester)
        request_id = uuid4()
        values = {
            "workspace_id": workspace.id,
            "task_id": task.id,
            "requester_id": requester.id,
            "approver_id": approver.id,
            "request_type": "TASK_UPDATE",
            "proposed_changes": "{}",
            "base_field_versions": "{}",
            "request_id": request_id,
        }
        sql = text(
            "INSERT INTO task_approval_requests "
            "(id, workspace_id, task_id, requester_id, approver_id, request_type, proposed_changes, "
            "base_field_versions, request_id, status) VALUES "
            "(:id, :workspace_id, :task_id, :requester_id, :approver_id, :request_type, "
            "CAST(:proposed_changes AS jsonb), CAST(:base_field_versions AS jsonb), :request_id, 'PENDING')"
        )
        session.execute(sql, {**values, "id": uuid4()})
        with pytest.raises(IntegrityError):
            session.execute(sql, {**values, "id": uuid4()})
