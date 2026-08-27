from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.models import MobileSession
from app.main import create_app


class FakeSmsProvider:
    def __init__(self) -> None:
        self.codes: dict[str, str] = {}

    def last_code_for(self, phone: str) -> str:
        return self.codes[phone]

    def send_otp(self, phone: str, code: str) -> None:
        self.codes[phone] = code


def test_mobile_me_refresh_and_logout_use_opaque_bearer_session(db_engine) -> None:
    app = create_app()
    app.state.engine = db_engine
    app.state.ready = True
    app.state.sms_provider = FakeSmsProvider()
    client = TestClient(app)
    client.post("/api/v1/auth/sms/send", json={"phone": "+8613800138000"})
    code = app.state.sms_provider.last_code_for("+8613800138000")
    verified = client.post(
        "/api/v1/auth/sms/verify",
        json={
            "phone": "+8613800138000",
            "code": code,
            "device": {"public_key_der": "AQID", "label": "Pixel"},
        },
    )
    tokens = verified.json()
    headers = {"Authorization": f"Bearer {tokens['access_token']}"}

    me = client.get("/api/v1/me", headers=headers)
    assert me.status_code == 200
    assert me.json()["phone"] == "+8613800138000"

    refreshed = client.post(
        "/api/v1/auth/mobile/refresh",
        json={"refresh_token": tokens["refresh_token"]},
    )
    assert refreshed.status_code == 200
    assert refreshed.json()["refresh_token"] != tokens["refresh_token"]

    logout = client.post(
        "/api/v1/auth/mobile/logout",
        headers={"Authorization": f"Bearer {refreshed.json()['access_token']}"},
    )
    assert logout.status_code == 204
    with Session(db_engine) as session:
        assert all(item.revoked_at is not None for item in session.scalars(select(MobileSession)).all())


def test_mobile_me_requires_active_bearer_session(db_engine) -> None:
    app = create_app()
    app.state.engine = db_engine
    app.state.ready = True
    app.state.sms_provider = FakeSmsProvider()
    client = TestClient(app)
    response = client.get("/api/v1/me")
    assert response.status_code == 401
    assert response.json()["code"] == "authentication_required"


def test_mobile_device_list_returns_only_the_callers_device_summary(db_engine) -> None:
    app = create_app()
    app.state.engine = db_engine
    app.state.ready = True
    app.state.sms_provider = FakeSmsProvider()
    client = TestClient(app)
    client.post("/api/v1/auth/sms/send", json={"phone": "+8613800138000"})
    code = app.state.sms_provider.last_code_for("+8613800138000")
    verified = client.post(
        "/api/v1/auth/sms/verify",
        json={
            "phone": "+8613800138000",
            "code": code,
            "device": {"public_key_der": "AQID", "label": "Pixel"},
        },
    )
    assert verified.status_code == 201, verified.text
    tokens = verified.json()

    response = client.get(
        "/api/v1/devices",
        headers={"Authorization": f"Bearer {tokens['access_token']}"},
    )

    assert response.status_code == 200, response.text
    devices = response.json()
    assert len(devices) == 1
    assert devices[0]["id"] == tokens["device_id"]
    assert devices[0]["label"] == "Pixel"
    assert devices[0]["platform"] == "ANDROID"
    assert devices[0]["status"] == "ACTIVE"
    assert devices[0]["is_current"] is True
    assert "public_key_der" not in devices[0]
