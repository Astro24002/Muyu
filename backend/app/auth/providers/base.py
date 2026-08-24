from __future__ import annotations

from typing import Protocol


class SmsDeliveryError(Exception):
    """The upstream SMS provider could not accept a message."""


class SmsProvider(Protocol):
    def send_otp(self, phone: str, code: str) -> None:
        """Deliver an OTP without returning or logging the OTP."""
