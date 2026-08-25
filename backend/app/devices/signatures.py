from __future__ import annotations

import base64
import json
from datetime import datetime
from uuid import UUID

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec


def b64url(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def signed_action_payload(
    *,
    action: str,
    approval_id: UUID,
    actor_device_id: UUID,
    workspace_id: UUID,
    nonce: bytes,
    expires_at: datetime,
) -> bytes:
    value = {
        "v": 1,
        "action": action,
        "approval_id": str(approval_id),
        "actor_device_id": str(actor_device_id),
        "workspace_id": str(workspace_id),
        "nonce": b64url(nonce),
        "expires_at": expires_at.isoformat(),
    }
    return json.dumps(value, ensure_ascii=True, separators=(",", ":"), sort_keys=True).encode("utf-8")


def verify_device_signature(public_key_der: bytes, payload: bytes, signature: bytes) -> bool:
    try:
        key = serialization.load_der_public_key(public_key_der)
    except (ValueError, TypeError) as error:
        raise ValueError("invalid device public key") from error
    if not isinstance(key, ec.EllipticCurvePublicKey) or not isinstance(key.curve, ec.SECP256R1):
        raise ValueError("device public key must use P-256")
    try:
        key.verify(signature, payload, ec.ECDSA(hashes.SHA256()))
    except InvalidSignature:
        return False
    return True
