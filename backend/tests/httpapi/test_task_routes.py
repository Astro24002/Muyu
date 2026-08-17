from app.auth.routes import UserResponse
from tests.httpapi.test_auth_routes import make_client


def auth_client(db_engine):
    client = make_client(db_engine)
    login = client.post(
        "/api/auth/login",
        json={"phone": "15028180169", "password": "shared-password"},
    )
    return client, {"Authorization": f"Bearer {login.json()['access_token']}"}


def member_ids(client, headers):
    users = client.get("/api/users", headers=headers).json()
    return [UserResponse.model_validate(item).id for item in users]


def task_payload(client, headers, *, title="整理旅行计划", parent_task_id=None):
    first, second = member_ids(client, headers)
    return {
        "title": title,
        "description": "确定交通和住宿",
        "assignee_ids": [str(first), str(second)],
        "current_handler_id": str(first),
        "parent_task_id": str(parent_task_id) if parent_task_id else None,
        "planned_start_at": "2026-09-01T09:00:00+08:00",
        "due_at": "2026-09-03T09:00:00+08:00",
        "estimated_minutes": 90,
    }


def test_task_http_flow_covers_crud_subtask_actions_and_events(db_engine) -> None:
    client, headers = auth_client(db_engine)

    created = client.post("/api/tasks", headers=headers, json=task_payload(client, headers))
    assert created.status_code == 201
    task = created.json()
    assert task["title"] == "整理旅行计划"
    assert task["status"] == "TODO"
    assert len(task["assignee_ids"]) == 2

    listed = client.get("/api/tasks", headers=headers)
    assert listed.status_code == 200
    assert listed.json()[0]["id"] == task["id"]

    updated = client.patch(
        f"/api/tasks/{task['id']}",
        headers=headers,
        json={"title": "确认旅行计划", "estimated_minutes": 120},
    )
    assert updated.status_code == 200
    assert updated.json()["title"] == "确认旅行计划"
    assert updated.json()["estimated_minutes"] == 120

    started = client.post(f"/api/tasks/{task['id']}/start", headers=headers)
    assert started.status_code == 200
    assert started.json()["status"] == "IN_PROGRESS"

    second_user = next(user_id for user_id in task["assignee_ids"] if user_id != task["current_handler_id"])
    transferred = client.post(
        f"/api/tasks/{task['id']}/transfer",
        headers=headers,
        json={"new_handler_id": second_user},
    )
    assert transferred.status_code == 200
    assert transferred.json()["current_handler_id"] == second_user

    child = client.post(
        "/api/tasks",
        headers=headers,
        json=task_payload(client, headers, title="预订酒店", parent_task_id=task["id"]),
    )
    assert child.status_code == 201
    children = client.get(
        "/api/tasks", headers=headers, params={"parent_task_id": task["id"]}
    )
    assert [item["id"] for item in children.json()] == [child.json()["id"]]

    completed = client.post(f"/api/tasks/{task['id']}/complete", headers=headers)
    assert completed.status_code == 200
    assert completed.json()["status"] == "DONE"

    events = client.get(f"/api/tasks/{task['id']}/events", headers=headers)
    assert events.status_code == 200
    assert [event["action"] for event in events.json()] == [
        "TASK_CREATED",
        "TASK_UPDATED",
        "TASK_STARTED",
        "TASK_HANDLER_CHANGED",
        "TASK_COMPLETED",
    ]


def test_task_http_maps_domain_rules_and_soft_delete(db_engine) -> None:
    client, headers = auth_client(db_engine)
    parent = client.post("/api/tasks", headers=headers, json=task_payload(client, headers)).json()
    child = client.post(
        "/api/tasks",
        headers=headers,
        json=task_payload(client, headers, title="子任务", parent_task_id=parent["id"]),
    ).json()

    blocked = client.delete(f"/api/tasks/{parent['id']}", headers=headers)
    assert blocked.status_code == 409
    assert blocked.json()["code"] == "TASK_HAS_SUBTASKS"

    deleted_child = client.delete(f"/api/tasks/{child['id']}", headers=headers)
    assert deleted_child.status_code == 204
    deleted_parent = client.delete(f"/api/tasks/{parent['id']}", headers=headers)
    assert deleted_parent.status_code == 204
    missing = client.get(f"/api/tasks/{parent['id']}", headers=headers)
    assert missing.status_code == 404
    assert missing.json()["code"] == "TASK_NOT_FOUND"


def test_task_order_and_authentication_contract(db_engine) -> None:
    client, headers = auth_client(db_engine)
    first = client.post("/api/tasks", headers=headers, json=task_payload(client, headers, title="A")).json()
    second = client.post("/api/tasks", headers=headers, json=task_payload(client, headers, title="B")).json()

    ordered = client.put(
        "/api/me/tasks/order",
        headers=headers,
        json={"task_ids": [second["id"], first["id"]]},
    )
    assert ordered.status_code == 200
    assert ordered.json()["task_ids"] == [second["id"], first["id"]]
    assert [item["title"] for item in client.get("/api/tasks", headers=headers).json()] == ["B", "A"]

    unauthorized = client.get("/api/tasks")
    assert unauthorized.status_code == 401
    assert unauthorized.json()["code"] == "UNAUTHORIZED"
