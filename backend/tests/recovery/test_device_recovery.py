from datetime import datetime, timezone

import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.enums import ApprovalStatus, DeviceStatus, MembershipStatus
from app.db.models import AndroidDevice, User, Workspace, WorkspaceCursor, WorkspaceMembership
from app.recovery.service import RecoveryConflict, RecoveryService


def _pair(session: Session) -> tuple[Workspace, User, User, AndroidDevice, AndroidDevice]:
    owner = User(phone="+14155552671")
    partner = User(phone="+14155552672")
    workspace = Workspace(name="Recovery")
    session.add_all([owner, partner, workspace])
    session.flush()
    owner_device = AndroidDevice(user_id=owner.id, public_key_der=b"owner", fingerprint="owner", status=DeviceStatus.ACTIVE)
    partner_device = AndroidDevice(user_id=partner.id, public_key_der=b"partner", fingerprint="partner", status=DeviceStatus.ACTIVE)
    session.add_all([owner_device, partner_device])
    session.add_all(
        [
            WorkspaceMembership(workspace_id=workspace.id, user_id=owner.id, member_slot=1, status=MembershipStatus.ACTIVE),
            WorkspaceMembership(workspace_id=workspace.id, user_id=partner.id, member_slot=2, status=MembershipStatus.ACTIVE),
            WorkspaceCursor(workspace_id=workspace.id, next_cursor=1),
        ]
    )
    session.flush()
    return workspace, owner, partner, owner_device, partner_device


def test_dual_device_loss_rotates_credentials_and_activates_new_devices(db_engine) -> None:
    with Session(db_engine) as session:
        workspace, owner, partner, old_owner, old_partner = _pair(session)
        new_owner = AndroidDevice(user_id=owner.id, public_key_der=b"new-owner", fingerprint="new-owner", status=DeviceStatus.PENDING)
        new_partner = AndroidDevice(user_id=partner.id, public_key_der=b"new-partner", fingerprint="new-partner", status=DeviceStatus.PENDING)
        session.add_all([new_owner, new_partner])
        session.flush()
        service = RecoveryService(session)
        request = service.start_device_loss(workspace.id, owner.id, new_owner.id)
        service.approve_device_loss(request.id, partner.id, new_partner.id)
        session.commit()

        for device in (old_owner, old_partner):
            session.refresh(device)
            assert device.status == DeviceStatus.REVOKED
        for device in (new_owner, new_partner):
            session.refresh(device)
            assert device.status == DeviceStatus.ACTIVE
        assert request.status == ApprovalStatus.APPROVED


def test_owner_cannot_revoke_their_last_active_device(db_engine) -> None:
    with Session(db_engine) as session:
        _workspace, owner, _partner, owner_device, _partner_device = _pair(session)
        with pytest.raises(RecoveryConflict) as error:
            RecoveryService(session).revoke_device(owner_device.id, owner.id, owner_device.id)
        assert error.value.code == "approval_not_allowed"
