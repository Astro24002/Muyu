from datetime import timedelta

from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.auth.tokens import TokenManager
from app.main import create_app
from app.user.service import seed_fixed_users


def make_client(db_engine):
    with Session(db_engine) as session:
        seed_fixed_users(session, "shared-password")

    app = create_app()
    app.state.engine = db_engine
    app.state.ready = True
    app.state.token_manager = TokenManager(
        access_secret="a" * 32,
        refresh_secret="r" * 32,
        access_ttl=timedelta(minutes=15),
        refresh_ttl=timedelta(days=30),
    )
    return TestClient(app)


def test_login_and_me_require_access_token(db_engine) -> None:
    client = make_client(db_engine)

    login = client.post(
        "/api/auth/login",
        json={"phone": "15028180169", "password": "shared-password"},
    )
    assert login.status_code == 200
    payload = login.json()
    assert payload["user"]["phone"] == "15028180169"
    assert payload["access_token"]
    assert payload["refresh_token"]

    missing = client.get("/api/me")
    assert missing.status_code == 401
    assert missing.json()["code"] == "UNAUTHORIZED"
    assert missing.headers["X-Request-ID"]

    me = client.get("/api/me", headers={"Authorization": f"Bearer {payload['access_token']}"})
    assert me.status_code == 200
    assert me.json()["phone"] == "15028180169"


def test_invalid_login_uses_uniform_unauthorized_error(db_engine) -> None:
    client = make_client(db_engine)

    response = client.post(
        "/api/auth/login",
        json={"phone": "00000000000", "password": "wrong-password"},
    )

    assert response.status_code == 401
    assert response.json()["code"] == "UNAUTHORIZED"
    assert response.headers["X-Request-ID"]


def test_refresh_rotates_and_logout_revokes_token(db_engine) -> None:
    client = make_client(db_engine)
    login = client.post(
        "/api/auth/login",
        json={"phone": "15028180169", "password": "shared-password"},
    ).json()

    refreshed = client.post("/api/auth/refresh", json={"refresh_token": login["refresh_token"]})
    assert refreshed.status_code == 200
    replacement = refreshed.json()
    assert replacement["refresh_token"] != login["refresh_token"]

    old_refresh = client.post("/api/auth/refresh", json={"refresh_token": login["refresh_token"]})
    assert old_refresh.status_code == 401

    logout = client.post("/api/auth/logout", json={"refresh_token": replacement["refresh_token"]})
    assert logout.status_code == 204
    revoked = client.post("/api/auth/refresh", json={"refresh_token": replacement["refresh_token"]})
    assert revoked.status_code == 401
