from __future__ import annotations

from datetime import datetime, timedelta, timezone
from importlib import import_module
from uuid import uuid4

import pytest
from sqlalchemy import inspect, select
from sqlalchemy.orm import Session

from app.db.enums import DeviceStatus, MembershipStatus, WebSessionStatus
from app.db.models import AndroidDevice, User, WebSession, Workspace, WorkspaceMembership
from app.recovery.service import RecoveryConflict, RecoveryService


def _schemas():
    """Load the new contract module so the initial red run is an assertion failure."""

    try:
        return import_module("app.workspaces.bootstrap_schemas")
    except ImportError as error:
        pytest.fail(f"bootstrap schemas are not exposed yet: {error}")


def test_device_registration_status_is_active_only_for_the_first_device() -> None:
    schemas = _schemas()

    assert schemas.device_status_for_device_count(0) is DeviceStatus.ACTIVE
    assert schemas.device_status_for_device_count(1) is DeviceStatus.PENDING
    assert schemas.device_status_for_device_count(2) is DeviceStatus.PENDING


def test_bootstrap_states_and_public_device_statuses_are_stable() -> None:
    schemas = _schemas()

    assert {state.value for state in schemas.BootstrapState} == {
        "NEEDS_PARTNER",
        "WAITING_FOR_PARTNER",
        "INVITED",
        "READY",
    }
    assert schemas.public_device_status(DeviceStatus.PENDING) == schemas.PublicDeviceStatus.UNVERIFIED
    assert schemas.public_device_status(DeviceStatus.ACTIVE) == schemas.PublicDeviceStatus.VERIFIED
    assert schemas.public_device_status(DeviceStatus.REVOKED) == schemas.PublicDeviceStatus.REVOKED

    payload = schemas.BootstrapPayload(
        state=schemas.BootstrapState.READY,
        workspace=None,
        invite=None,
        device={"status": "VERIFIED", "can_write": True},
    )
    assert payload.device.status is schemas.PublicDeviceStatus.VERIFIED
    assert payload.device.can_write is True


def test_persisted_device_and_web_session_statuses_remain_compatible() -> None:
    assert [status.value for status in DeviceStatus] == ["PENDING", "ACTIVE", "REVOKED"]
    assert [status.value for status in WebSessionStatus] == ["ACTIVE", "REVOKED", "EXPIRED"]


def test_web_sessions_are_not_part_of_the_android_device_collection(db_engine) -> None:
    with Session(db_engine) as session:
        user = User(phone=f"+1555{uuid4().int % 10_000_000:07d}")
        workspace = Workspace(name="Contract")
        session.add_all([user, workspace])
        session.flush()
        device = AndroidDevice(
            user_id=user.id,
            public_key_der=b"contract-device",
            fingerprint=uuid4().hex,
            status=DeviceStatus.ACTIVE,
        )
        session.add(device)
        session.flush()
        session.add(
            WorkspaceMembership(
                workspace_id=workspace.id,
                user_id=user.id,
                member_slot=1,
                status=MembershipStatus.ACTIVE,
            )
        )
        session.add(
            WebSession(
                user_id=user.id,
                workspace_id=workspace.id,
                approving_device_id=device.id,
                session_digest=uuid4().hex,
                status=WebSessionStatus.ACTIVE,
                expires_at=datetime.now(timezone.utc) + timedelta(hours=1),
            )
        )
        session.commit()

        devices = session.scalars(select(AndroidDevice).where(AndroidDevice.user_id == user.id)).all()
        assert len(devices) == 1
        assert all(not isinstance(item, WebSession) for item in devices)


def test_current_device_revoke_uses_the_stable_error_code(db_engine) -> None:
    with Session(db_engine) as session:
        user = User(phone=f"+1555{uuid4().int % 10_000_000:07d}")
        workspace = Workspace(name="Contract")
        session.add_all([user, workspace])
        session.flush()
        device = AndroidDevice(
            user_id=user.id,
            public_key_der=b"current-device",
            fingerprint=uuid4().hex,
            status=DeviceStatus.ACTIVE,
        )
        session.add(device)
        session.flush()
        session.add(
            WorkspaceMembership(
                workspace_id=workspace.id,
                user_id=user.id,
                member_slot=1,
                status=MembershipStatus.ACTIVE,
            )
        )
        session.flush()

        with pytest.raises(RecoveryConflict) as error:
            RecoveryService(session).revoke_device(device.id, user.id, device.id)

        assert error.value.code == "approval_not_allowed"


def test_cleanup_indexes_cover_status_and_expiry(db_engine) -> None:
    inspector = inspect(db_engine)

    indexes = {
        index["name"]: tuple(index["column_names"])
        for table in ("web_sessions", "web_login_challenges")
        for index in inspector.get_indexes(table)
    }
    assert indexes["ix_web_sessions_status_expires_at"] == ("status", "expires_at")
    assert indexes["ix_web_login_challenges_status_expires_at"] == ("status", "expires_at")
