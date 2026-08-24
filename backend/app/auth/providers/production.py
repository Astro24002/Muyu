from __future__ import annotations

import json
import urllib.error
import urllib.request

from app.auth.providers.base import SmsDeliveryError


class ProductionSmsProvider:
    """Minimal JSON adapter; credentials and message content never enter logs."""

    def __init__(self, endpoint: str, api_key: str, *, timeout: float = 10.0) -> None:
        self.endpoint = endpoint
        self.api_key = api_key
        self.timeout = timeout

    def send_otp(self, phone: str, code: str) -> None:
        payload = json.dumps({"phone": phone, "code": code}).encode("utf-8")
        request = urllib.request.Request(
            self.endpoint,
            data=payload,
            headers={"Authorization": f"Bearer {self.api_key}", "Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                if response.status >= 300:
                    raise SmsDeliveryError("SMS provider rejected delivery")
        except (urllib.error.URLError, TimeoutError, SmsDeliveryError) as error:
            if isinstance(error, SmsDeliveryError):
                raise
            raise SmsDeliveryError("SMS provider unavailable") from error
