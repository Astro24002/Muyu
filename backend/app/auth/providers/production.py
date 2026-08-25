from __future__ import annotations

import json
import urllib.error
import urllib.request
from urllib.parse import urlencode

from app.auth.providers.base import SmsDeliveryError


class ProductionSmsProvider:
    """Guoyangyun Aliyun-market adapter for production SMS delivery."""

    def __init__(
        self,
        endpoint: str,
        appcode: str,
        *,
        sms_sign_id: str,
        template_id: str,
        validity_minutes: int = 5,
        timeout: float = 10.0,
    ) -> None:
        self.endpoint = endpoint
        self.appcode = appcode
        self.sms_sign_id = sms_sign_id
        self.template_id = template_id
        self.validity_minutes = validity_minutes
        self.timeout = timeout

    def send_otp(self, phone: str, code: str) -> None:
        payload = urlencode(
            {
                "mobile": phone,
                "smsSignId": self.sms_sign_id,
                "templateId": self.template_id,
                "param": f"**code**:{code},**minute**:{self.validity_minutes}",
            }
        ).encode("utf-8")
        request = urllib.request.Request(
            self.endpoint,
            data=payload,
            headers={
                "Authorization": f"APPCODE {self.appcode}",
                "Content-Type": "application/x-www-form-urlencoded",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                if response.status >= 300:
                    raise SmsDeliveryError("SMS provider rejected delivery")
                try:
                    result = json.loads(response.read().decode("utf-8"))
                except (UnicodeDecodeError, json.JSONDecodeError) as error:
                    raise SmsDeliveryError("SMS provider returned invalid response") from error
                if not isinstance(result, dict) or str(result.get("code")) != "0":
                    raise SmsDeliveryError("SMS provider rejected delivery")
        except (urllib.error.URLError, TimeoutError, SmsDeliveryError) as error:
            if isinstance(error, SmsDeliveryError):
                raise
            raise SmsDeliveryError("SMS provider unavailable") from error
