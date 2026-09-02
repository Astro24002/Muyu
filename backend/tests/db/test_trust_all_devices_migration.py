from __future__ import annotations

from collections.abc import Iterator
from datetime import datetime, timedelta, timezone
from pathlib import Path
from uuid import UUID, uuid4

import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine, make_url
from sqlalchemy.orm import Session
from sqlalchemy.pool import NullPool

from app.db.enums import ApprovalStatus, DeviceStatus, MembershipStatus
from app.db.models import (
    ActivityEvent,
    AndroidDevice,
    DeviceAuthorizationRequest,
    MobileSession,
    User,
    Workspace,
    WorkspaceMembership,
)


def _config(database_url: str, schema: str) -> Config:
    backend_dir = Path(__file__).resolve().parents[2]
    config = Config(str(backend_dir / "alembic.ini"))
    config.set_main_option("script_location", str(backend_dir / "alembic"))
    config.set_main_option("sqlalchemy.url", database_url.replace("%", "%%"))
    config.attributes["schema"] = schema
    return config


@pytest.fixture
def at_0005(database_url: str) -> Iterator[Engine]:
    schema = f"test_{uuid4().hex}"
    admin_engine = create_engine(database_url, pool_pre_ping=True, poolclass=NullPool)
    with admin_engine.begin() as connection:
        connection.execute(text(f'CREATE SCHEMA "{schema}"'))

    schema_url = make_url(database_url).update_query_dict(
        {"options": f"-csearch_path={schema}"}
    )
    engine = create_engine(schema_url, pool_pre_ping=True, poolclass=NullPool)
    try:
        command.upgrade(_config(database_url, schema), "0005_remove_task_assignees")
        yield engine
    finally:
        engine.dispose()
        with admin_engine.begin() as connection:
            connection.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        admin_engine.dispose()


def _seed_devices(engine: Engine) -> dict[str, UUID | datetime]:
    now = datetime.now(timezone.utc)
    revoked_at = now - timedelta(days=2)
    with Session(engine) as session:
        user = User(phone=f"+1555{uuid4().int % 10_000_000:07d}")
        workspace = Workspace()
        session.add_all([user, workspace])
        session.flush()
        session.add(
            WorkspaceMembership(
                workspace_id=workspace.id,
                user_id=user.id,
                member_slot=1,
                status=MembershipStatus.ACTIVE,
            )
        )

        pending = AndroidDevice(
            user_id=user.id,
            public_key_der=b"pending-key",
            fingerprint="pending-fingerprint",
            label="Pending device",
            status=DeviceStatus.PENDING,
            enrolled_at=None,
        )
        active = AndroidDevice(
            user_id=user.id,
            public_key_der=b"active-key",
            fingerprint="active-fingerprint",
            label="Active device",
            status=DeviceStatus.ACTIVE,
            enrolled_at=now - timedelta(days=10),
        )
        revoked = AndroidDevice(
            user_id=user.id,
            public_key_der=b"revoked-key",
            fingerprint="revoked-fingerprint",
            label="Revoked device",
            status=DeviceStatus.REVOKED,
            enrolled_at=now - timedelta(days=20),
            revoked_at=revoked_at,
        )
        session.add_all([pending, active, revoked])
        session.flush()

        mobile_session = MobileSession(
            user_id=user.id,
            device_id=revoked.id,
            refresh_token_digest="revoked-session-digest",
            expires_at=now + timedelta(days=1),
            revoked_at=revoked_at,
        )
        audit_event = ActivityEvent(
            workspace_id=workspace.id,
            actor_user_id=user.id,
            actor_device_id=revoked.id,
            event_type="device_revoked",
            payload={"preserve": True},
            created_at=revoked_at,
        )
        pending_request = DeviceAuthorizationRequest(
            workspace_id=workspace.id,
            candidate_device_id=pending.id,
            status=ApprovalStatus.PENDING,
            safety_code_digest="pending-request-digest",
            expires_at=now + timedelta(hours=1),
        )
        approved_request = DeviceAuthorizationRequest(
            workspace_id=workspace.id,
            candidate_device_id=active.id,
            status=ApprovalStatus.APPROVED,
            safety_code_digest="approved-request-digest",
            expires_at=now + timedelta(hours=1),
            approved_at=now - timedelta(minutes=5),
        )
        session.add_all([mobile_session, audit_event, pending_request, approved_request])
        session.commit()

        return {
            "pending_id": pending.id,
            "active_id": active.id,
            "revoked_id": revoked.id,
            "revoked_at": revoked_at,
            "mobile_session_id": mobile_session.id,
            "audit_event_id": audit_event.id,
            "pending_request_id": pending_request.id,
            "approved_request_id": approved_request.id,
        }


def _upgrade_to_head(engine: Engine, database_url: str) -> None:
    with engine.connect() as connection:
        schema = connection.scalar(text("SELECT current_schema()"))
    command.upgrade(_config(database_url, schema), "head")


def test_upgrade_activates_non_revoked_pending_devices_and_preserves_revoked_audit(
    at_0005: Engine, database_url: str
) -> None:
    data = _seed_devices(at_0005)

    _upgrade_to_head(at_0005, database_url)

    with Session(at_0005) as session:
        pending = session.get(AndroidDevice, data["pending_id"])
        active = session.get(AndroidDevice, data["active_id"])
        revoked = session.get(AndroidDevice, data["revoked_id"])
        assert pending is not None and pending.status == DeviceStatus.ACTIVE
        assert pending.enrolled_at is not None
        assert active is not None and active.status == DeviceStatus.ACTIVE
        assert revoked is not None
        assert revoked.status == DeviceStatus.REVOKED
        assert revoked.revoked_at == data["revoked_at"]

        mobile_session = session.get(MobileSession, data["mobile_session_id"])
        assert mobile_session is not None
        assert mobile_session.device_id == data["revoked_id"]
        assert mobile_session.revoked_at == data["revoked_at"]

        audit_event = session.get(ActivityEvent, data["audit_event_id"])
        assert audit_event is not None
        assert audit_event.actor_device_id == data["revoked_id"]
        assert audit_event.payload == {"preserve": True}


def test_upgrade_expires_pending_device_authorization_requests(
    at_0005: Engine, database_url: str
) -> None:
    data = _seed_devices(at_0005)

    _upgrade_to_head(at_0005, database_url)

    with Session(at_0005) as session:
        pending = session.get(DeviceAuthorizationRequest, data["pending_request_id"])
        approved = session.get(DeviceAuthorizationRequest, data["approved_request_id"])
        assert pending is not None
        assert pending.status == ApprovalStatus.EXPIRED
        assert pending.expires_at <= datetime.now(timezone.utc)
        assert approved is not None
        assert approved.status == ApprovalStatus.APPROVED
