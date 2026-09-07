from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session
from fastapi.testclient import TestClient

from app.db.enums import DeviceStatus
from app.db.models import AndroidDevice, MobileSession, SmsVerificationChallenge, User
from app.main import create_app


class FakeSmsProvider:
    def __init__(self) -> None:
        self.codes: dict[str, str] = {}
        self.fail_delivery = False

    def last_code_for(self, phone: str) -> str:
        return self.codes[phone]

    def send_otp(self, phone: str, code: str) -> None:
        if self.fail_delivery:
            from app.auth.providers.base import SmsDeliveryError

            raise SmsDeliveryError("failed")
        self.codes[phone] = code


def make_client(db_engine):
    app = create_app()
    app.state.engine = db_engine
    app.state.ready = True
    app.state.sms_provider = FakeSmsProvider()
    return TestClient(app)


def verify_payload(code: str) -> dict[str, object]:
    return {
        "phone": "+86 138 0013 8000",
        "code": code,
        "device": {
            "public_key_der": "AQID",
            "label": "Pixel test",
        },
    }


def test_sms_verification_creates_cloud_user_device_and_opaque_session(db_engine) -> None:
    client = make_client(db_engine)
    sent = client.post("/api/v1/auth/sms/send", json={"phone": "+86 138 0013 8000"})
    assert sent.status_code == 202
    code = client.app.state.sms_provider.last_code_for("+8613800138000")

    verified = client.post("/api/v1/auth/sms/verify", json=verify_payload(code))
    assert verified.status_code == 201
    body = verified.json()
    assert body["token_type"] == "bearer"
    assert body["access_token"]
    assert body["refresh_token"]

    with Session(db_engine) as session:
        user = session.scalar(select(User).where(User.phone == "+8613800138000"))
        assert user is not None
        assert session.scalar(select(AndroidDevice).where(AndroidDevice.user_id == user.id)) is not None
        stored = session.scalar(select(MobileSession))
        assert stored is not None
        assert body["refresh_token"] not in stored.refresh_token_digest
        challenge = session.scalar(select(SmsVerificationChallenge))
        assert challenge is not None
        assert challenge.code_digest != code


def test_sms_verification_is_single_use(db_engine) -> None:
    client = make_client(db_engine)
    client.post("/api/v1/auth/sms/send", json={"phone": "+8613800138000"})
    code = client.app.state.sms_provider.last_code_for("+8613800138000")
    first = client.post("/api/v1/auth/sms/verify", json=verify_payload(code))
    second = client.post("/api/v1/auth/sms/verify", json=verify_payload(code))
    assert first.status_code == 201
    assert second.status_code == 422
    assert second.json()["code"] == "invalid_otp"


def test_sms_send_and_verify_normalize_an_eleven_digit_phone(db_engine) -> None:
    client = make_client(db_engine)
    response = client.post("/api/v1/auth/sms/send", json={"phone": "13800138000"})
    assert response.status_code == 202
    code = client.app.state.sms_provider.last_code_for("+8613800138000")

    verified = client.post(
        "/api/v1/auth/sms/verify",
        json={
            "phone": "13800138000",
            "code": code,
            "device": {"public_key_der": "AQID", "label": "local-number"},
        },
    )
    assert verified.status_code == 201, verified.text


def test_sms_send_rejects_an_invalid_phone(db_engine) -> None:
    client = make_client(db_engine)
    response = client.post("/api/v1/auth/sms/send", json={"phone": "12345"})
    assert response.status_code == 422
    assert response.json()["code"] == "invalid_request"


def test_latest_otp_wins_after_resend(db_engine, monkeypatch: pytest.MonkeyPatch) -> None:
    codes = iter(("111111", "222222"))
    monkeypatch.setattr("app.auth.service.generate_otp", lambda: next(codes))
    client = make_client(db_engine)
    phone = "+8613800138000"

    assert client.post("/api/v1/auth/sms/send", json={"phone": phone}).status_code == 202
    assert client.post("/api/v1/auth/sms/send", json={"phone": phone}).status_code == 202
    assert client.app.state.sms_provider.last_code_for(phone) == "222222"

    verified = client.post(
        "/api/v1/auth/sms/verify",
        json={
            "phone": phone,
            "code": "222222",
            "device": {"public_key_der": "AQID", "label": "resend"},
        },
    )
    assert verified.status_code == 201, verified.text


def test_sms_attempt_limit_rejects_wrong_codes(db_engine) -> None:
    client = make_client(db_engine)
    client.post("/api/v1/auth/sms/send", json={"phone": "+8613800138000"})
    for _ in range(5):
        response = client.post("/api/v1/auth/sms/verify", json=verify_payload("000000"))
    assert response.status_code == 422
    assert response.json()["code"] == "invalid_otp"


def test_sms_send_provider_failure_does_not_persist_challenge(db_engine) -> None:
    client = make_client(db_engine)
    client.app.state.sms_provider.fail_delivery = True
    response = client.post("/api/v1/auth/sms/send", json={"phone": "+8613800138000"})
    assert response.status_code == 503
    with Session(db_engine) as session:
        assert session.scalars(select(SmsVerificationChallenge)).all() == []


def test_existing_workspace_user_gets_a_trusted_second_device(db_engine) -> None:
    client = make_client(db_engine)
    client.post("/api/v1/auth/sms/send", json={"phone": "+8613800138000"})
    code = client.app.state.sms_provider.last_code_for("+8613800138000")
    first = client.post("/api/v1/auth/sms/verify", json=verify_payload(code)).json()
    workspace = client.post(
        "/api/v1/workspaces",
        headers={"Authorization": f"Bearer {first['access_token']}"},
        json={"name": "Shared"},
    )
    assert workspace.status_code == 201

    client.post("/api/v1/auth/sms/send", json={"phone": "+8613800138000"})
    replacement_code = client.app.state.sms_provider.last_code_for("+8613800138000")
    replacement = client.post(
        "/api/v1/auth/sms/verify",
        json={
            "phone": "+8613800138000",
            "code": replacement_code,
            "device": {"public_key_der": "BAUG", "label": "Replacement"},
        },
    )
    assert replacement.status_code == 201
    assert replacement.json()["device_status"] == "VERIFIED"
    assert replacement.json()["can_write"] is True
    with Session(db_engine) as session:
        devices = session.scalars(select(AndroidDevice).order_by(AndroidDevice.created_at)).all()
        assert len(devices) == 2
        assert devices[-1].status == DeviceStatus.ACTIVE
        assert devices[-1].enrolled_at is not None
