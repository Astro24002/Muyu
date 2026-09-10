from __future__ import annotations

from datetime import datetime, timezone
from uuid import UUID, uuid4

from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.db.models import Task, Workspace
from app.main import create_app

from .test_device_readonly_permissions import _headers, _ready_workspace
from .test_lightweight_routes import FakeSmsProvider


def _client(db_engine) -> TestClient:
    app = create_app()
    app.state.engine = db_engine
    app.state.ready = True
    app.state.sms_provider = FakeSmsProvider()
    return TestClient(app)


def _create_task(
    client: TestClient,
    headers: dict[str, str],
    title: str,
    *,
    due_at: str | None = None,
) -> dict[str, object]:
    payload: dict[str, object] = {
        "request_id": str(uuid4()),
        "title": title,
        "quadrant": "Q2",
        "labels": ["工作"],
    }
    if due_at is not None:
        payload["due_at"] = due_at
    response = client.post("/api/v1/tasks", headers=headers, json=payload)
    assert response.status_code == 201, response.text
    return response.json()


def _transition(
    client: TestClient,
    headers: dict[str, str],
    task: dict[str, object],
    target_status: str,
    **metadata: object,
) -> dict[str, object]:
    response = client.post(
        f"/api/v1/tasks/{task['id']}/transition",
        headers=headers,
        json={
            "request_id": str(uuid4()),
            "target_status": target_status,
            "base_status_version": task["status_version"],
            **metadata,
        },
    )
    assert response.status_code in {200, 202}, response.text
    payload = response.json()
    if response.status_code == 202:
        assert payload["pending"] is True
        return payload["task"]
    return payload


def _section(body: dict[str, object], name: str) -> dict[str, object]:
    section = body[name]
    assert isinstance(section, dict)
    assert isinstance(section["items"], list)
    assert isinstance(section["has_more"], bool)
    return section


def test_home_requires_an_authenticated_actor(db_engine) -> None:
    response = _client(db_engine).get("/api/v1/home")

    assert response.status_code == 401
    assert response.json()["code"] == "authentication_required"


def test_home_returns_only_the_actor_actionable_tasks_and_omits_deleted_or_foreign_rows(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    owner_headers = _headers(owner)
    partner_headers = _headers(partner)

    owner_todo = _create_task(client, owner_headers, "Owner TODO")
    owner_progress = _transition(
        client,
        owner_headers,
        _create_task(client, owner_headers, "Owner in progress"),
        "IN_PROGRESS",
    )
    owner_blocked = _transition(
        client,
        owner_headers,
        _create_task(client, owner_headers, "Owner blocked"),
        "BLOCKED",
        blocked_reason="Waiting for a confirmation",
        resume_handler_id=owner["user"]["id"],
    )
    partner_review = _transition(
        client,
        partner_headers,
        _transition(
            client,
            partner_headers,
            _create_task(client, partner_headers, "Review for owner"),
            "IN_PROGRESS",
        ),
        "REVIEW",
    )
    partner_todo = _create_task(client, partner_headers, "Partner ordinary TODO")
    partner_progress = _transition(
        client,
        partner_headers,
        _create_task(client, partner_headers, "Partner ordinary progress"),
        "IN_PROGRESS",
    )
    deleted = _create_task(client, owner_headers, "Deleted owner task")
    deleted_response = client.post(
        f"/api/v1/tasks/{deleted['id']}/lifecycle",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "action": "delete",
            "base_lifecycle_version": deleted["lifecycle_version"],
        },
    )
    assert deleted_response.status_code == 200, deleted_response.text
    foreign = _create_task(client, owner_headers, "Foreign workspace task")

    with Session(db_engine) as session:
        foreign_workspace = Workspace(name="Foreign")
        session.add(foreign_workspace)
        session.flush()
        foreign_task = session.get(Task, UUID(str(foreign["id"])))
        assert foreign_task is not None
        foreign_task.workspace_id = foreign_workspace.id
        session.commit()

    response = client.get("/api/v1/home", headers=owner_headers)

    assert response.status_code == 200, response.text
    body = response.json()
    current = _section(body, "current_tasks")
    blocked = _section(body, "blocked_tasks")
    review = _section(body, "review_tasks")
    assert {item["id"] for item in current["items"]} == {owner_todo["id"], owner_progress["id"]}
    assert [item["id"] for item in blocked["items"]] == [owner_blocked["id"]]
    assert [item["id"] for item in review["items"]] == [partner_review["id"]]
    assert current["has_more"] is False
    assert blocked["has_more"] is False
    assert review["has_more"] is False
    # The review submission automatically creates an incoming acceptance
    # request for the owner of the home page.
    assert body["pending_approval_count"] == 1

    visible_ids = {
        item["id"]
        for section in (current, blocked, review)
        for item in section["items"]
    }
    assert {partner_todo["id"], partner_progress["id"], deleted["id"], foreign["id"]}.isdisjoint(visible_ids)


def test_home_caps_each_section_and_counts_only_incoming_pending_approvals(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    owner_headers = _headers(owner)
    partner_headers = _headers(partner)

    for index in range(6):
        _create_task(client, owner_headers, f"Current {index}")
    for index in range(4):
        _transition(
            client,
            owner_headers,
            _create_task(client, owner_headers, f"Blocked {index}"),
            "BLOCKED",
            blocked_reason=f"Reason {index}",
            resume_handler_id=owner["user"]["id"],
        )
    for index in range(4):
        review = _transition(
            client,
            partner_headers,
            _create_task(client, partner_headers, f"Review {index}"),
            "IN_PROGRESS",
        )
        _transition(client, partner_headers, review, "REVIEW")

    owner_task = _create_task(client, owner_headers, "Incoming approval source")
    incoming = client.patch(
        f"/api/v1/tasks/{owner_task['id']}",
        headers=partner_headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"title": "Partner proposal"},
            "base_field_versions": {"title": owner_task["field_versions"]["title"]},
        },
    )
    assert incoming.status_code == 202, incoming.text

    partner_task = _create_task(client, partner_headers, "Outgoing approval source")
    outgoing = client.patch(
        f"/api/v1/tasks/{partner_task['id']}",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"title": "Owner proposal"},
            "base_field_versions": {"title": partner_task["field_versions"]["title"]},
        },
    )
    assert outgoing.status_code == 202, outgoing.text

    response = client.get("/api/v1/home", headers=owner_headers)

    assert response.status_code == 200, response.text
    body = response.json()
    current = _section(body, "current_tasks")
    blocked = _section(body, "blocked_tasks")
    review = _section(body, "review_tasks")
    assert len(current["items"]) == 5
    assert current["has_more"] is True
    assert len(blocked["items"]) == 3
    assert blocked["has_more"] is True
    assert len(review["items"]) == 3
    assert review["has_more"] is True
    # Four review submissions plus the partner's title change are waiting for
    # this user.
    assert body["pending_approval_count"] == 5


def test_home_sorts_current_tasks_by_due_urgency_then_update_time_and_id(db_engine) -> None:
    client = _client(db_engine)
    owner, _partner = _ready_workspace(client)
    headers = _headers(owner)
    overdue = _create_task(client, headers, "Overdue", due_at="2020-01-01T09:00:00+00:00")
    due_newer = _create_task(client, headers, "Due newer", due_at="2099-01-01T09:00:00+00:00")
    due_older = _create_task(client, headers, "Due older", due_at="2099-01-01T09:00:00+00:00")
    no_due = _create_task(client, headers, "No due date")

    with Session(db_engine) as session:
        session.get(Task, UUID(str(overdue["id"]))).updated_at = datetime(2026, 1, 1, tzinfo=timezone.utc)
        session.get(Task, UUID(str(due_newer["id"]))).updated_at = datetime(2030, 1, 2, tzinfo=timezone.utc)
        session.get(Task, UUID(str(due_older["id"]))).updated_at = datetime(2030, 1, 1, tzinfo=timezone.utc)
        # Keep this fixture as a legacy row so the null-date compatibility
        # ordering remains covered after new creates receive a default date.
        no_due_task = session.get(Task, UUID(str(no_due["id"])))
        no_due_task.due_at = None
        no_due_task.updated_at = datetime(2040, 1, 1, tzinfo=timezone.utc)
        session.commit()

    response = client.get("/api/v1/home", headers=headers)

    assert response.status_code == 200, response.text
    titles = [item["title"] for item in _section(response.json(), "current_tasks")["items"]]
    assert titles == ["Overdue", "Due newer", "Due older", "No due date"]


def test_home_uses_task_id_as_the_current_task_sort_tie_breaker(db_engine) -> None:
    client = _client(db_engine)
    owner, _partner = _ready_workspace(client)
    headers = _headers(owner)
    first = _create_task(client, headers, "Same due first", due_at="2099-01-01T09:00:00+00:00")
    second = _create_task(client, headers, "Same due second", due_at="2099-01-01T09:00:00+00:00")

    with Session(db_engine) as session:
        updated_at = datetime(2030, 1, 1, tzinfo=timezone.utc)
        session.get(Task, UUID(str(first["id"]))).updated_at = updated_at
        session.get(Task, UUID(str(second["id"]))).updated_at = updated_at
        session.commit()

    response = client.get("/api/v1/home", headers=headers)

    assert response.status_code == 200, response.text
    ids = [item["id"] for item in _section(response.json(), "current_tasks")["items"]]
    assert ids == sorted([first["id"], second["id"]])
