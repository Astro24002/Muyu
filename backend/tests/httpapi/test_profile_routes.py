from fastapi.testclient import TestClient

from app.auth.providers.fake import FakeSmsProvider
from app.main import create_app


def _client(db_engine) -> TestClient:
    app = create_app()
    app.state.engine = db_engine
    app.state.ready = True
    app.state.sms_provider = FakeSmsProvider()
    return TestClient(app)


def _login(client: TestClient) -> dict[str, object]:
    phone = "+8613800138000"
    sent = client.post("/api/v1/auth/sms/send", json={"phone": phone})
    assert sent.status_code == 202, sent.text
    provider = client.app.state.sms_provider
    verified = client.post(
        "/api/v1/auth/sms/verify",
        json={
            "phone": phone,
            "code": provider.last_code_for(phone),
            "device": {"public_key_der": "AQID", "label": "Pixel"},
        },
    )
    assert verified.status_code == 201, verified.text
    return verified.json()


def _headers(session: dict[str, object]) -> dict[str, str]:
    return {"Authorization": f"Bearer {session['access_token']}"}


def test_patch_me_trims_display_name_and_returns_updated_mobile_user(db_engine) -> None:
    client = _client(db_engine)
    session = _login(client)

    response = client.patch(
        "/api/v1/me",
        headers=_headers(session),
        json={"display_name": "  Muyu  "},
    )

    assert response.status_code == 200, response.text
    payload = response.json()
    assert payload["id"] == session["user"]["id"]
    assert payload["phone"] == "+8613800138000"
    assert payload["display_name"] == "Muyu"
    assert payload["device_id"] == session["device_id"]
    assert payload["device_status"] == "VERIFIED"
    assert payload["can_write"] is True

    persisted = client.get("/api/v1/me", headers=_headers(session))
    assert persisted.status_code == 200, persisted.text
    assert persisted.json()["display_name"] == "Muyu"


def test_patch_me_rejects_unknown_profile_fields_with_validation_envelope(db_engine) -> None:
    client = _client(db_engine)
    session = _login(client)

    response = client.patch(
        "/api/v1/me",
        headers=_headers(session),
        json={"display_name": "Muyu", "phone": "+8613800138999"},
    )

    assert response.status_code == 422, response.text
    payload = response.json()
    assert payload["code"] == "VALIDATION_ERROR"
    assert payload["message"] == "request validation failed"
    assert any(item["loc"] == ["body", "phone"] for item in payload["details"])


def test_patch_me_rejects_display_name_over_the_server_limit(db_engine) -> None:
    client = _client(db_engine)
    session = _login(client)

    response = client.patch(
        "/api/v1/me",
        headers=_headers(session),
        json={"display_name": "x" * 121},
    )

    assert response.status_code == 422, response.text
    payload = response.json()
    assert payload["code"] == "VALIDATION_ERROR"
    assert any(
        item["loc"] == ["body", "display_name"] for item in payload["details"]
    )
