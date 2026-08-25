from fastapi.testclient import TestClient

from app.main import create_app


def test_local_web_client_cors_preflight_is_allowed() -> None:
    client = TestClient(create_app())

    response = client.options(
        "/api/v1/auth/sms/send",
        headers={
            "Origin": "http://localhost:3000",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "content-type",
        },
    )

    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == "http://localhost:3000"
    assert "POST" in response.headers["access-control-allow-methods"]
