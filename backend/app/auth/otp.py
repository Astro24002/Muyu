from __future__ import annotations

import hmac
import secrets


def generate_otp() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


def digest_otp(code: str, pepper: str) -> str:
    return hmac.new(pepper.encode("utf-8"), code.encode("ascii"), "sha256").hexdigest()


def verify_otp(code: str, digest: str, pepper: str) -> bool:
    return len(code) == 6 and code.isascii() and code.isdigit() and hmac.compare_digest(
        digest_otp(code, pepper), digest
    )
