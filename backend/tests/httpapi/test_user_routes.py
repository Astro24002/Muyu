from fastapi.testclient import TestClient

from tests.httpapi.test_auth_routes import make_client


def login(client: TestClient) -> dict[str, str]:
    response = client.post(
        "/api/auth/login",
        json={"phone": "15028180169", "password": "shared-password"},
    )
    return response.json()


def test_profile_patch_whitelist_and_users_listing(db_engine) -> None:
    client = make_client(db_engine)
    tokens = login(client)
    headers = {"Authorization": f"Bearer {tokens['access_token']}"}

    updated = client.patch("/api/me", headers=headers, json={"nickname": "新的昵称", "role": "伙伴"})
    assert updated.status_code == 200
    assert updated.json()["nickname"] == "新的昵称"
    assert updated.json()["role"] == "伙伴"

    immutable = client.patch("/api/me", headers=headers, json={"phone": "00000000000"})
    assert immutable.status_code == 422
    assert immutable.json()["code"] == "VALIDATION_ERROR"

    users = client.get("/api/users", headers=headers)
    assert users.status_code == 200
    assert [user["phone"] for user in users.json()] == ["15028180169", "15068128726"]


def test_health_check_reports_ready_state(db_engine) -> None:
    client = make_client(db_engine)

    response = client.get("/healthz")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
