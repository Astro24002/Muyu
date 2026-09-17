from __future__ import annotations

from datetime import datetime, timezone
from uuid import UUID, uuid4

from sqlalchemy.orm import Session

from app.db.models import Task, User

from .test_home_routes import _client, _create_task, _headers, _ready_workspace, _transition


def test_task_query_filters_status_handler_and_searches_labels_and_owner(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    owner_headers = _headers(owner)
    partner_headers = _headers(partner)

    mine = _create_task(client, owner_headers, "旅行清单")
    other = _create_task(client, partner_headers, "采购材料")
    with Session(db_engine) as session:
        row = session.get(Task, UUID(str(mine["id"])))
        assert row is not None
        row.next_step_text = "确认周末交通方案"
        session.commit()
    _transition(client, owner_headers, mine, "IN_PROGRESS")
    _transition(client, partner_headers, other, "BLOCKED", blocked_reason="等待确认", resume_handler_id=partner["user"]["id"])

    response = client.get(
        "/api/v1/tasks?q=工作&status=open&handler=mine&limit=10",
        headers=owner_headers,
    )

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["query"] == {
        "q": "工作",
        "status": "open",
        "handler": "mine",
        "include_history": False,
    }
    assert [item["id"] for item in body["items"]] == [mine["id"]]

    with Session(db_engine) as session:
        user = session.get(User, UUID(str(owner["user"]["id"])))
        assert user is not None
        user.display_name = "小木鱼"
        session.commit()
    owner_search = client.get("/api/v1/tasks?q=小木鱼", headers=owner_headers)
    assert owner_search.status_code == 200, owner_search.text
    assert [item["id"] for item in owner_search.json()["items"]] == [mine["id"]]

    next_step_search = client.get(
        "/api/v1/tasks?q=交通方案",
        headers=owner_headers,
    )
    assert next_step_search.status_code == 200, next_step_search.text
    assert [item["id"] for item in next_step_search.json()["items"]] == [mine["id"]]


def test_task_query_keyset_cursor_is_bound_and_history_includes_done_cancelled(db_engine) -> None:
    client = _client(db_engine)
    owner, _partner = _ready_workspace(client)
    headers = _headers(owner)
    tasks = [_create_task(client, headers, f"历史 {index}") for index in range(3)]

    done = _transition(client, headers, tasks[0], "IN_PROGRESS")
    with Session(db_engine) as session:
        row = session.get(Task, UUID(str(done["id"])))
        assert row is not None
        row.status = "DONE"
        row.updated_at = datetime(2020, 1, 1, tzinfo=timezone.utc)
        session.commit()
    cancelled = _transition(client, headers, tasks[1], "CANCELLED")
    with Session(db_engine) as session:
        row = session.get(Task, UUID(str(cancelled["id"])))
        assert row is not None
        row.updated_at = datetime(2020, 1, 2, tzinfo=timezone.utc)
        session.commit()

    first = client.get("/api/v1/tasks?include_history=true&limit=2", headers=headers)
    assert first.status_code == 200, first.text
    first_body = first.json()
    assert first_body["query"]["status"] == "all"
    assert first_body["has_more"] is True
    assert len(first_body["items"]) == 2

    second = client.get(
        "/api/v1/tasks?include_history=true&limit=2&after=" + first_body["next_cursor"],
        headers=headers,
    )
    assert second.status_code == 200, second.text
    assert {item["id"] for item in first_body["items"]}.isdisjoint(
        {item["id"] for item in second.json()["items"]}
    )

    mismatch = client.get(
        "/api/v1/tasks?status=done&limit=2&after=" + first_body["next_cursor"],
        headers=headers,
    )
    assert mismatch.status_code == 422, mismatch.text
    assert mismatch.json()["code"] == "invalid_task_cursor"


def test_task_query_handoff_pending_excludes_deleted_tasks_and_legacy_list_stays_a_list(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    owner_headers = _headers(owner)
    partner_headers = _headers(partner)
    task = _create_task(client, owner_headers, "待接棒")
    transfer = client.patch(
        f"/api/v1/tasks/{task['id']}",
        headers=partner_headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"current_handler_id": partner["user"]["id"]},
            "base_field_versions": {"current_handler_id": task["field_versions"]["current_handler_id"]},
        },
    )
    assert transfer.status_code == 202, transfer.text

    pending = client.get("/api/v1/tasks?status=handoff_pending", headers=owner_headers)
    assert pending.status_code == 200, pending.text
    assert [item["id"] for item in pending.json()["items"]] == [task["id"]]

    legacy = client.get("/api/v1/tasks", headers=owner_headers)
    assert legacy.status_code == 200, legacy.text
    assert isinstance(legacy.json(), list)

    deleted = client.post(
        f"/api/v1/tasks/{task['id']}/lifecycle",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "action": "delete",
            "base_lifecycle_version": task["lifecycle_version"],
        },
    )
    assert deleted.status_code == 200, deleted.text
    assert client.get("/api/v1/tasks?status=handoff_pending", headers=owner_headers).json()["items"] == []


def test_task_query_rejects_unknown_filters(db_engine) -> None:
    client = _client(db_engine)
    owner, _partner = _ready_workspace(client)
    headers = _headers(owner)
    for query in ("status=unknown", "handler=unknown"):
        response = client.get("/api/v1/tasks?" + query, headers=headers)
        assert response.status_code == 422, response.text
        assert response.json()["code"] == "invalid_task_query"
