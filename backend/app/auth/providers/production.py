from __future__ import annotations

import json
import urllib.error
import urllib.request
from urllib.parse import urlencode, urlsplit, urlunsplit

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
        # Guoyangyun's Aliyun-market endpoint expects these fields in the
        # query string (the provider's reference request uses ``params``),
        # while our auth layer deliberately keeps phones in E.164 form.
        # Convert only at this external boundary to the provider's required
        # mainland-China 11-digit representation.
        mobile = _guoyangyun_mobile(phone)
        query = urlencode(
            {
                "mobile": mobile,
                "smsSignId": self.sms_sign_id,
                "templateId": self.template_id,
                "param": f"**code**:{code},**minute**:{self.validity_minutes}",
            }
        )
        endpoint = urlsplit(self.endpoint)
        request_url = urlunsplit(
            endpoint._replace(
                query=f"{endpoint.query}&{query}" if endpoint.query else query,
            )
        )
        request = urllib.request.Request(
            request_url,
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


def _guoyangyun_mobile(phone: str) -> str:
    """Convert an internal E.164 Chinese phone to Guoyangyun's local form."""

    compact = phone.strip().replace(" ", "")
    if compact.startswith("+86"):
        return compact[3:]
    return compact
