from __future__ import annotations

from app.auth.providers.base import SmsDeliveryError


class FakeSmsProvider:
    """Deterministic in-process provider for tests and local development."""

    def __init__(self) -> None:
        self._codes: dict[str, str] = {}
        self.fail_delivery = False

    def send_otp(self, phone: str, code: str) -> None:
        if self.fail_delivery:
            raise SmsDeliveryError("SMS provider rejected delivery")
        self._codes[phone] = code

    def last_code_for(self, phone: str) -> str:
        return self._codes[phone]
