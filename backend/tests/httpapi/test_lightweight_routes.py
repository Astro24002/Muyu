from uuid import uuid4

from fastapi.testclient import TestClient

from app.main import create_app


class FakeSmsProvider:
    def __init__(self) -> None:
        self.codes: dict[str, str] = {}

    def last_code_for(self, phone: str) -> str:
        return self.codes[phone]

    def send_otp(self, phone: str, code: str) -> None:
        self.codes[phone] = code


def _client(db_engine):
    app = create_app()
    app.state.engine = db_engine
    app.state.ready = True
    app.state.sms_provider = FakeSmsProvider()
    return TestClient(app)


def _authenticated(client: TestClient) -> str:
    phone = "+8613800138000"
    sent = client.post("/api/v1/auth/sms/send", json={"phone": phone})
    assert sent.status_code == 202, sent.text
    code = client.app.state.sms_provider.last_code_for(phone)
    verified = client.post(
        "/api/v1/auth/sms/verify",
        json={
            "phone": phone,
            "code": code,
            "device": {"public_key_der": "AQID", "label": "contract-test"},
        },
    )
    assert verified.status_code == 201, verified.text
    token = verified.json()["access_token"]
    workspace = client.post(
        "/api/v1/workspaces",
        headers={"Authorization": f"Bearer {token}"},
        json={"name": "Contract"},
    )
    assert workspace.status_code == 201, workspace.text
    return token


def test_lightweight_tasks_require_authentication(db_engine) -> None:
    client = _client(db_engine)
    response = client.get("/api/v1/tasks")
    assert response.status_code == 401
    assert response.json()["code"] == "authentication_required"


def test_create_transition_and_nested_task_contract(db_engine) -> None:
    client = _client(db_engine)
    token = _authenticated(client)
    headers = {"Authorization": f"Bearer {token}"}

    parent = client.post(
        "/api/v1/tasks",
        headers=headers,
        json={"request_id": str(uuid4()), "title": "Parent"},
    )
    assert parent.status_code == 201, parent.text
    parent_body = parent.json()
    assert parent_body["status"] == "TODO"
    child = client.post(
        "/api/v1/tasks",
        headers=headers,
        json={
            "request_id": str(uuid4()),
            "title": "Child",
            "parent_task_id": parent_body["id"],
            "assignee_ids": [parent_body["current_handler_id"]],
        },
    )
    assert child.status_code == 201, child.text

    transition = client.post(
        f"/api/v1/tasks/{parent_body['id']}/transition",
        headers=headers,
        json={
            "request_id": str(uuid4()),
            "target_status": "DONE",
            "base_status_version": parent_body["status_version"],
        },
    )
    assert transition.status_code == 200, transition.text
    assert transition.json()["status"] == "DONE"
    assert transition.json()["status_version"] == parent_body["status_version"] + 1

    nested = client.post(
        "/api/v1/tasks",
        headers=headers,
        json={
            "request_id": str(uuid4()),
            "title": "Nested",
            "parent_task_id": child.json()["id"],
        },
    )
    assert nested.status_code == 422, nested.text
    assert nested.json()["code"] == "nested_task_not_allowed"

