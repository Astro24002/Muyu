from __future__ import annotations

from uuid import uuid4

from fastapi.testclient import TestClient

from .test_home_routes import _client, _headers, _ready_workspace


def test_task_next_step_is_persisted_and_versioned(db_engine) -> None:
    client = _client(db_engine)
    owner, _ = _ready_workspace(client)
    headers = _headers(owner)
    created = client.post(
        "/api/v1/tasks",
        headers=headers,
        json={
            "request_id": str(uuid4()),
            "title": "准备旅行",
            "next_step_text": "确认周末可用的交通方案",
            "quadrant": "Q2",
            "labels": ["工作"],
        },
    )
    assert created.status_code == 201, created.text
    task = created.json()
    assert task["next_step_text"] == "确认周末可用的交通方案"
    version = task["field_versions"]["next_step_text"]

    updated = client.patch(
        f"/api/v1/tasks/{task['id']}",
        headers=headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"next_step_text": "发消息确认集合时间"},
            "base_field_versions": {"next_step_text": version},
        },
    )
    assert updated.status_code == 200, updated.text
    assert updated.json()["next_step_text"] == "发消息确认集合时间"

    fetched = client.get(f"/api/v1/tasks/{task['id']}", headers=headers)
    assert fetched.status_code == 200, fetched.text
    assert fetched.json()["next_step_text"] == "发消息确认集合时间"


def test_task_next_step_rejects_blank_and_overlong_values(db_engine) -> None:
    client = _client(db_engine)
    owner, _ = _ready_workspace(client)
    headers = _headers(owner)
    for value in ("   ", "x" * 91):
        response = client.post(
            "/api/v1/tasks",
            headers=headers,
            json={
                "request_id": str(uuid4()),
                "title": "边界任务",
                "next_step_text": value,
                "quadrant": "Q2",
                "labels": ["工作"],
            },
        )
        assert response.status_code == 422, response.text
        assert response.json()["code"] == "invalid_request"


def test_legacy_task_create_without_next_step_remains_read_compatible(db_engine) -> None:
    client = _client(db_engine)
    owner, _ = _ready_workspace(client)
    response = client.post(
        "/api/v1/tasks",
        headers=_headers(owner),
        json={
            "request_id": str(uuid4()),
            "title": "旧客户端任务",
            "quadrant": "Q2",
            "labels": ["工作"],
        },
    )
    assert response.status_code == 201, response.text
    assert response.json()["next_step_text"] is None
