from datetime import datetime, timezone
from uuid import uuid4

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.enums import ApprovalStatus, DeviceStatus, MembershipStatus
from app.db.models import AndroidDevice, User, WorkspaceClassification, WorkspaceMembership
from app.devices.signatures import signed_action_payload
from app.workspaces.service import WorkspaceService


def _keypair() -> tuple[ec.EllipticCurvePrivateKey, bytes]:
    private = ec.generate_private_key(ec.SECP256R1())
    return private, private.public_key().public_bytes(
        serialization.Encoding.DER,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )


def test_first_workspace_invite_and_signed_partner_approval(db_engine) -> None:
    with Session(db_engine) as session:
        owner = User(phone="+14155552671")
        invited = User(phone="+14155552672")
        session.add_all([owner, invited])
        session.flush()
        owner_key, owner_der = _keypair()
        candidate_key, candidate_der = _keypair()
        owner_device = AndroidDevice(
            user_id=owner.id,
            public_key_der=owner_der,
            fingerprint="owner",
            status=DeviceStatus.ACTIVE,
        )
        candidate_device = AndroidDevice(
            user_id=invited.id,
            public_key_der=candidate_der,
            fingerprint="candidate",
            status=DeviceStatus.PENDING,
        )
        session.add_all([owner_device, candidate_device])
        session.flush()

        service = WorkspaceService(session, now=lambda: datetime.now(timezone.utc))
        workspace = service.create_workspace(owner.id, name="Shared")
        invite = service.create_invite(workspace.id, owner.id, invited.phone)
        request, safety_code = service.accept_invite(invite.id, invited.id, candidate_device.id)
        assert safety_code.isdigit() and len(safety_code) == 6
        challenge = service.begin_approval(request.id, owner_device.id)
        payload = signed_action_payload(
            action="DEVICE_APPROVE",
            approval_id=request.id,
            actor_device_id=owner_device.id,
            workspace_id=workspace.id,
            nonce=challenge.nonce,
            expires_at=challenge.expires_at,
        )
        signature = owner_key.sign(payload, ec.ECDSA(hashes.SHA256()))
        service.approve(request.id, owner_device.id, signature)
        session.commit()

        membership = session.scalar(
            select(WorkspaceMembership).where(
                WorkspaceMembership.workspace_id == workspace.id,
                WorkspaceMembership.user_id == invited.id,
            )
        )
        session.refresh(candidate_device)
        assert membership is not None
        assert membership.status == MembershipStatus.ACTIVE
        assert candidate_device.status == DeviceStatus.ACTIVE
        assert request.status == ApprovalStatus.APPROVED
        default_classification = session.scalar(
            select(WorkspaceClassification).where(
                WorkspaceClassification.workspace_id == workspace.id,
                WorkspaceClassification.normalized_name == "默认",
            )
        )
        assert default_classification is not None
        assert default_classification.name == "默认"
        assert default_classification.created_by == owner.id
