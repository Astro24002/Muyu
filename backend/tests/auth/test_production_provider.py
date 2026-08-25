from __future__ import annotations

import json
from urllib.parse import parse_qs

import pytest

from app.auth.providers.base import SmsDeliveryError
from app.auth.providers.production import ProductionSmsProvider


class _Response:
    status = 200

    def __init__(self, body: bytes) -> None:
        self._body = body

    def read(self) -> bytes:
        return self._body

    def __enter__(self) -> "_Response":
        return self

    def __exit__(self, *args: object) -> None:
        return None


def test_guoyangyun_provider_sends_form_request_and_accepts_business_success(monkeypatch: pytest.MonkeyPatch) -> None:
    captured: dict[str, object] = {}

    def fake_urlopen(request, timeout: float):
        captured["url"] = request.full_url
        captured["headers"] = dict(request.headers)
        captured["body"] = request.data
        captured["timeout"] = timeout
        return _Response(json.dumps({"code": "0", "msg": "成功"}).encode())

    monkeypatch.setattr("urllib.request.urlopen", fake_urlopen)
    provider = ProductionSmsProvider(
        "https://gyytz.market.alicloudapi.com/sms/smsSend",
        "test-appcode",
        sms_sign_id="sign-1",
        template_id="template-1",
        validity_minutes=5,
    )

    provider.send_otp("+8613800138000", "123456")

    assert captured["url"] == "https://gyytz.market.alicloudapi.com/sms/smsSend"
    headers = captured["headers"]
    assert headers["Authorization"] == "APPCODE test-appcode"
    assert headers["Content-type"] == "application/x-www-form-urlencoded"
    body = parse_qs(bytes(captured["body"]).decode())
    assert body == {
        "mobile": ["+8613800138000"],
        "smsSignId": ["sign-1"],
        "templateId": ["template-1"],
        "param": ["**code**:123456,**minute**:5"],
    }


def test_guoyangyun_provider_rejects_http_success_with_business_error(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        "urllib.request.urlopen",
        lambda request, timeout: _Response(json.dumps({"code": "QuotaExhausted", "msg": "失败"}).encode()),
    )
    provider = ProductionSmsProvider(
        "https://gyytz.market.alicloudapi.com/sms/smsSend",
        "test-appcode",
        sms_sign_id="sign-1",
        template_id="template-1",
    )

    with pytest.raises(SmsDeliveryError, match="rejected"):
        provider.send_otp("+8613800138000", "123456")


def test_guoyangyun_provider_rejects_malformed_business_response(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        "urllib.request.urlopen",
        lambda request, timeout: _Response(b"not-json"),
    )
    provider = ProductionSmsProvider(
        "https://gyytz.market.alicloudapi.com/sms/smsSend",
        "test-appcode",
        sms_sign_id="sign-1",
        template_id="template-1",
    )

    with pytest.raises(SmsDeliveryError, match="invalid response"):
        provider.send_otp("+8613800138000", "123456")
