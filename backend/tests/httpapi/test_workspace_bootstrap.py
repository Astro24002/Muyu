from fastapi.testclient import TestClient

from app.main import create_app


class FakeSmsProvider:
    def __init__(self) -> None:
        self.codes: dict[str, str] = {}

    def send_otp(self, phone: str, code: str) -> None:
        self.codes[phone] = code

    def last_code_for(self, phone: str) -> str:
        return self.codes[phone]


def _headers_for_first_device(client: TestClient, app) -> tuple[dict[str, str], str]:
    phone = "+8613800138001"
    assert client.post("/api/v1/auth/sms/send", json={"phone": phone}).status_code == 202
    code = app.state.sms_provider.last_code_for(phone)
    verified = client.post(
        "/api/v1/auth/sms/verify",
        json={
            "phone": phone,
            "code": code,
            "device": {"public_key_der": "AQID", "label": "Bootstrap Pixel"},
        },
    )
    assert verified.status_code == 201
    body = verified.json()
    return {"Authorization": f"Bearer {body['access_token']}"}, body["user"]["id"]


def test_first_active_device_can_create_exactly_one_workspace(db_engine) -> None:
    app = create_app()
    app.state.engine = db_engine
    app.state.ready = True
    app.state.sms_provider = FakeSmsProvider()
    client = TestClient(app)
    headers, owner_id = _headers_for_first_device(client, app)

    assert client.get("/api/v1/workspaces/current", headers=headers).json() is None

    created = client.post("/api/v1/workspaces", headers=headers, json={})
    assert created.status_code == 201
    assert created.json()["status"] == "ACTIVE"

    current = client.get("/api/v1/workspaces/current", headers=headers)
    assert current.status_code == 200
    assert current.json()["id"] == created.json()["id"]
    members = current.json()["members"]
    assert len(members) == 1
    assert members[0]["member_slot"] == 1
    assert members[0]["user_id"] == owner_id

    repeated = client.post("/api/v1/workspaces", headers=headers, json={})
    assert repeated.status_code == 409
    assert repeated.json()["code"] == "workspace_limit_reached"
