from uuid import UUID, uuid4

from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.main import create_app
from tests.classification_fixtures import seed_approved_classification


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
    with Session(client.app.state.engine) as session:
        seed_approved_classification(
            session,
            UUID(str(workspace.json()["id"])),
            UUID(str(verified.json()["user"]["id"])),
        )
        session.commit()
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
        json={"request_id": str(uuid4()), "title": "Parent", "quadrant": "Q1", "labels": ["工作"]},
    )
    assert parent.status_code == 201, parent.text
    parent_body = parent.json()
    assert parent_body["status"] == "TODO"
    assert "assignee_ids" not in parent_body
    child = client.post(
        "/api/v1/tasks",
        headers=headers,
        json={
            "request_id": str(uuid4()),
            "title": "Child",
            "quadrant": "Q1",
            "labels": ["工作"],
            "parent_task_id": parent_body["id"],
        },
    )
    assert child.status_code == 201, child.text
    assert "assignee_ids" not in child.json()

    transition = client.post(
        f"/api/v1/tasks/{parent_body['id']}/transition",
        headers=headers,
        json={
            "request_id": str(uuid4()),
            "target_status": "IN_PROGRESS",
            "base_status_version": parent_body["status_version"],
        },
    )
    assert transition.status_code == 200, transition.text
    assert transition.json()["status"] == "IN_PROGRESS"
    assert transition.json()["status_version"] == parent_body["status_version"] + 1

    stale = client.post(
        f"/api/v1/tasks/{parent_body['id']}/transition",
        headers=headers,
        json={
            "request_id": str(uuid4()),
            "target_status": "TODO",
            "base_status_version": parent_body["status_version"],
        },
    )
    assert stale.status_code == 409, stale.text
    assert stale.json()["details"]["conflicts"][0]["field"] == "status"

    nested = client.post(
        "/api/v1/tasks",
        headers=headers,
        json={
            "request_id": str(uuid4()),
            "title": "Nested",
            "quadrant": "Q1",
            "labels": ["工作"],
            "parent_task_id": child.json()["id"],
        },
    )
    assert nested.status_code == 422, nested.text
    assert nested.json()["code"] == "nested_task_not_allowed"


def test_removed_assignee_fields_are_rejected_with_validation_envelope(db_engine) -> None:
    client = _client(db_engine)
    token = _authenticated(client)
    headers = {"Authorization": f"Bearer {token}"}

    created = client.post(
        "/api/v1/tasks",
        headers=headers,
        json={"request_id": str(uuid4()), "title": "Owner task", "quadrant": "Q1", "labels": ["工作"]},
    )
    assert created.status_code == 201, created.text
    task = created.json()

    create_with_removed_field = client.post(
        "/api/v1/tasks",
        headers=headers,
        json={
            "request_id": str(uuid4()),
            "title": "Legacy task",
            "quadrant": "Q1",
            "assignee_ids": [task["current_handler_id"]],
        },
    )
    patch_with_removed_field = client.patch(
        f"/api/v1/tasks/{task['id']}",
        headers=headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"assignee_ids": [task["current_handler_id"]]},
            "base_field_versions": {"assignee_ids": 1},
        },
    )

    for response in (create_with_removed_field, patch_with_removed_field):
        assert response.status_code == 422, response.text
        body = response.json()
        assert body["code"] == "VALIDATION_ERROR"
        assert body["message"] == "request validation failed"
        assert isinstance(body["details"], list)
        assert body["details"]


def test_conflict_resolution_is_idempotent_and_proposed_value_is_versioned(db_engine) -> None:
    client = _client(db_engine)
    token = _authenticated(client)
    headers = {"Authorization": f"Bearer {token}"}

    created = client.post(
        "/api/v1/tasks",
        headers=headers,
        json={"request_id": str(uuid4()), "title": "Original", "quadrant": "Q1", "labels": ["工作"]},
    )
    assert created.status_code == 201, created.text
    task = created.json()
    updated = client.patch(
        f"/api/v1/tasks/{task['id']}",
        headers=headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"title": "Current"},
            "base_field_versions": {"title": task["field_versions"]["title"]},
        },
    )
    assert updated.status_code == 200, updated.text
    stale = client.patch(
        f"/api/v1/tasks/{task['id']}",
        headers=headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"title": "Proposed"},
            "base_field_versions": {"title": task["field_versions"]["title"]},
        },
    )
    assert stale.status_code == 409, stale.text
    conflict_id = stale.json()["details"]["conflicts"][0]["id"]
    listed = client.get(f"/api/v1/tasks/{task['id']}/conflicts", headers=headers)
    assert listed.status_code == 200, listed.text
    assert listed.json()[0]["status"] == "OPEN"

    request_id = str(uuid4())
    resolved = client.post(
        f"/api/v1/tasks/{task['id']}/conflicts/{conflict_id}/resolve",
        headers=headers,
        json={"request_id": request_id, "resolution": "current"},
    )
    assert resolved.status_code == 200, resolved.text
    assert resolved.json()["title"] == "Current"
    first_cursor = resolved.json()["cursor"]
    replay = client.post(
        f"/api/v1/tasks/{task['id']}/conflicts/{conflict_id}/resolve",
        headers=headers,
        json={"request_id": request_id, "resolution": "current"},
    )
    assert replay.status_code == 200, replay.text
    assert replay.json()["cursor"] == first_cursor
    mismatch = client.post(
        f"/api/v1/tasks/{task['id']}/conflicts/{conflict_id}/resolve",
        headers=headers,
        json={"request_id": request_id, "resolution": "proposed"},
    )
    assert mismatch.status_code == 409, mismatch.text
    assert mismatch.json()["code"] == "idempotency_key_reused"

    second = client.post(
        "/api/v1/tasks",
        headers=headers,
        json={"request_id": str(uuid4()), "title": "Second", "quadrant": "Q1", "labels": ["工作"]},
    ).json()
    current = client.patch(
        f"/api/v1/tasks/{second['id']}",
        headers=headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"title": "Second current"},
            "base_field_versions": {"title": second["field_versions"]["title"]},
        },
    ).json()
    stale_second = client.patch(
        f"/api/v1/tasks/{second['id']}",
        headers=headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"title": "Second proposed"},
            "base_field_versions": {"title": second["field_versions"]["title"]},
        },
    )
    second_conflict_id = stale_second.json()["details"]["conflicts"][0]["id"]
    latest = client.patch(
        f"/api/v1/tasks/{second['id']}",
        headers=headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"title": "Second latest"},
            "base_field_versions": {"title": current["field_versions"]["title"]},
        },
    )
    assert latest.status_code == 200, latest.text
    stale_resolution = client.post(
        f"/api/v1/tasks/{second['id']}/conflicts/{second_conflict_id}/resolve",
        headers=headers,
        json={"request_id": str(uuid4()), "resolution": "proposed"},
    )
    assert stale_resolution.status_code == 409, stale_resolution.text


def test_conflict_creation_http_replay_preserves_the_original_409_projection(db_engine) -> None:
    client = _client(db_engine)
    token = _authenticated(client)
    headers = {"Authorization": f"Bearer {token}"}
    created = client.post(
        "/api/v1/tasks",
        headers=headers,
        json={"request_id": str(uuid4()), "title": "Replay", "quadrant": "Q1", "labels": ["工作"]},
    )
    assert created.status_code == 201, created.text
    task = created.json()
    current = client.patch(
        f"/api/v1/tasks/{task['id']}",
        headers=headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"title": "Current"},
            "base_field_versions": {"title": task["field_versions"]["title"]},
        },
    )
    assert current.status_code == 200, current.text

    request_id = str(uuid4())
    payload = {
        "request_id": request_id,
        "changes": {"title": "Proposed"},
        "base_field_versions": {"title": task["field_versions"]["title"]},
    }
    first = client.patch(f"/api/v1/tasks/{task['id']}", headers=headers, json=payload)
    replay = client.patch(f"/api/v1/tasks/{task['id']}", headers=headers, json=payload)

    assert first.status_code == 409, first.text
    assert replay.status_code == first.status_code
    assert replay.json() == first.json()
    assert replay.json()["code"] == "field_conflict"
    assert replay.json()["details"]["conflicts"][0]["current_snapshot"]["title"] == "Current"
    assert replay.json()["details"]["cursor"] > current.json()["cursor"]
