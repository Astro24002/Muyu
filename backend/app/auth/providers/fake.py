from __future__ import annotations

from app.auth.providers.base import SmsDeliveryError


class FakeSmsProvider:
    """Deterministic in-process provider for tests and local development."""

    def __init__(self, code_override: str | None = None) -> None:
        self._codes: dict[str, str] = {}
        self.code_override = code_override
        self.fail_delivery = False

    def send_otp(self, phone: str, code: str) -> None:
        if self.fail_delivery:
            raise SmsDeliveryError("SMS provider rejected delivery")
        self._codes[phone] = self.code_override or code

    def last_code_for(self, phone: str) -> str:
        return self._codes[phone]
