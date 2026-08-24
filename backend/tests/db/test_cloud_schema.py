from __future__ import annotations

from datetime import datetime, timezone
from uuid import uuid4

import pytest
from sqlalchemy import inspect, text
from sqlalchemy.exc import IntegrityError
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


def _active_member(session: Session, workspace, user, slot: int):
    from app.db.enums import MembershipStatus
    from app.db.models import WorkspaceMembership

    member = WorkspaceMembership(
        workspace_id=workspace.id,
        user_id=user.id,
        member_slot=slot,
        status=MembershipStatus.ACTIVE,
    )
    session.add(member)
    session.flush()
    return member


def test_cloud_migration_exposes_authoritative_tables_and_indexes(db_engine) -> None:
    inspector = inspect(db_engine)

    expected_tables = {
        "users",
        "android_devices",
        "mobile_sessions",
        "workspaces",
        "workspace_memberships",
        "workspace_invites",
        "device_authorization_requests",
        "device_authorization_challenges",
        "recovery_requests",
        "phone_change_requests",
        "web_login_challenges",
        "web_sessions",
        "idempotency_records",
        "workspace_cursors",
        "workspace_change_log",
        "tasks",
        "task_operations",
        "task_conflicts",
        "task_comments",
        "delay_records",
        "important_dates",
        "recurrence_rules",
        "activity_events",
    }
    assert expected_tables.issubset(inspector.get_table_names())

    assert {index["name"] for index in inspector.get_indexes("users")} >= {
        "uq_users_normalized_phone",
    }
    assert {index["name"] for index in inspector.get_indexes("workspace_memberships")} >= {
        "uq_active_workspace_member_per_user",
        "uq_active_workspace_member_slot",
    }
    assert {index["name"] for index in inspector.get_indexes("workspace_change_log")} >= {
        "uq_workspace_change_cursor",
    }


def test_workspace_rejects_a_third_active_member(db_engine) -> None:
    with Session(db_engine) as session:
        workspace = _workspace(session)
        _active_member(session, workspace, _user(session), 1)
        _active_member(session, workspace, _user(session), 2)

        with pytest.raises(IntegrityError):
            _active_member(session, workspace, _user(session), 1)


def test_user_cannot_have_two_active_workspaces(db_engine) -> None:
    with Session(db_engine) as session:
        user = _user(session)
        first = _workspace(session)
        second = _workspace(session)
        _active_member(session, first, user, 1)

        with pytest.raises(IntegrityError):
            _active_member(session, second, user, 1)


def test_workspace_request_id_is_unique(db_engine) -> None:
    with Session(db_engine) as session:
        workspace = _workspace(session)
        request_id = uuid4()
        session.execute(
            text(
                "INSERT INTO idempotency_records "
                "(id, workspace_id, request_id, route, request_fingerprint, response_status, response_body, expires_at) "
                "VALUES (:id, :workspace_id, :request_id, :route, :fingerprint, :status, :body, :expires_at)"
            ),
            {
                "id": uuid4(),
                "workspace_id": workspace.id,
                "request_id": request_id,
                "route": "/api/v1/tasks",
                "fingerprint": "digest",
                "status": 201,
                "body": "{}",
                "expires_at": datetime.now(timezone.utc),
            },
        )
        with pytest.raises(IntegrityError):
            session.execute(
                text(
                    "INSERT INTO idempotency_records "
                    "(id, workspace_id, request_id, route, request_fingerprint, response_status, response_body, expires_at) "
                    "VALUES (:id, :workspace_id, :request_id, :route, :fingerprint, :status, :body, :expires_at)"
                ),
                {
                    "id": uuid4(),
                    "workspace_id": workspace.id,
                    "request_id": request_id,
                    "route": "/api/v1/tasks",
                    "fingerprint": "digest",
                    "status": 201,
                    "body": "{}",
                    "expires_at": datetime.now(timezone.utc),
                },
            )


def test_web_session_requires_active_approving_device(db_engine) -> None:
    with Session(db_engine) as session:
        user = _user(session)
        workspace = _workspace(session)
        _active_member(session, workspace, user, 1)
        from app.db.enums import DeviceStatus, WebSessionStatus
        from app.db.models import AndroidDevice, WebSession

        device = AndroidDevice(user_id=user.id, status=DeviceStatus.REVOKED, public_key_der=b"key")
        session.add(device)
        session.flush()

        with pytest.raises(IntegrityError):
            session.add(
                WebSession(
                    user_id=user.id,
                    workspace_id=workspace.id,
                    approving_device_id=device.id,
                    session_digest="digest",
                    status=WebSessionStatus.ACTIVE,
                    expires_at=datetime.now(timezone.utc),
                )
            )
            session.flush()


def test_cursor_repository_allocates_monotonic_values_without_committing(db_engine) -> None:
    with Session(db_engine) as session:
        workspace = _workspace(session)
        from app.db.repositories.base import Repository

        repository = Repository(session)
        first = repository.allocate_workspace_cursor(workspace.id)
        second = repository.allocate_workspace_cursor(workspace.id)
        assert (first, second) == (1, 2)
        assert session.in_transaction()
