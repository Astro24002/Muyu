from datetime import datetime, timezone
from uuid import uuid4

import pytest
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec

from app.devices.signatures import (
    signed_action_payload,
    verify_device_signature,
)


def test_signed_action_payload_is_deterministic_and_verifiable() -> None:
    private = ec.generate_private_key(ec.SECP256R1())
    public_der = private.public_key().public_bytes(
        serialization.Encoding.DER,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    approval_id = uuid4()
    device_id = uuid4()
    workspace_id = uuid4()
    expires_at = datetime(2026, 1, 1, tzinfo=timezone.utc)
    payload = signed_action_payload(
        action="DEVICE_APPROVE",
        approval_id=approval_id,
        actor_device_id=device_id,
        workspace_id=workspace_id,
        nonce=b"nonce",
        expires_at=expires_at,
    )
    signature = private.sign(payload, ec.ECDSA(hashes.SHA256()))

    assert verify_device_signature(public_der, payload, signature)
    assert payload == signed_action_payload(
        action="DEVICE_APPROVE",
        approval_id=approval_id,
        actor_device_id=device_id,
        workspace_id=workspace_id,
        nonce=b"nonce",
        expires_at=expires_at,
    )


def test_signature_rejects_tampering_and_non_p256_keys() -> None:
    private = ec.generate_private_key(ec.SECP256R1())
    public_der = private.public_key().public_bytes(
        serialization.Encoding.DER,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    signature = private.sign(b"payload", ec.ECDSA(hashes.SHA256()))
    assert not verify_device_signature(public_der, b"tampered", signature)
    with pytest.raises(ValueError, match="P-256"):
        other = ec.generate_private_key(ec.SECP384R1())
        verify_device_signature(
            other.public_key().public_bytes(
                serialization.Encoding.DER,
                serialization.PublicFormat.SubjectPublicKeyInfo,
            ),
            b"payload",
            signature,
        )
