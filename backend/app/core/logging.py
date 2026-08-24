from __future__ import annotations

from collections.abc import Mapping
from typing import Any


SENSITIVE_KEYS = frozenset({
    "authorization",
    "cookie",
    "set-cookie",
    "otp",
    "otp_code",
    "qr_nonce",
    "qr_proof",
    "phone",
    "phone_number",
    "access_token",
    "refresh_token",
    "session_token",
    "signature",
})


def redact_sensitive_data(value: Any) -> Any:
    """Return structured request data without credentials or identifying secrets."""

    if isinstance(value, Mapping):
        return {
            str(key): "[REDACTED]" if str(key).lower() in SENSITIVE_KEYS else redact_sensitive_data(item)
            for key, item in value.items()
        }
    if isinstance(value, list):
        return [redact_sensitive_data(item) for item in value]
    if isinstance(value, tuple):
        return tuple(redact_sensitive_data(item) for item in value)
    return value
