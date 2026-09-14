from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import UUID, uuid4

from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.enums import TaskStatus
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
    if target_status == "REVIEW" and "review_content" not in metadata:
        metadata["review_content"] = "测试验收内容"
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


def _moment_section(body: dict[str, object], name: str) -> dict[str, object]:
    moment = body["moment"]
    assert isinstance(moment, dict)
    section = moment[name]
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


def test_home_moment_groups_both_members_once_and_filters_non_progress_states(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    owner_headers = _headers(owner)
    partner_headers = _headers(partner)

    owner_todo = _create_task(client, owner_headers, "Owner TODO")
    owner_progress = _transition(
        client,
        owner_headers,
        _create_task(client, owner_headers, "Owner progress"),
        "IN_PROGRESS",
    )
    owner_blocked = _transition(
        client,
        owner_headers,
        _create_task(client, owner_headers, "Owner blocked"),
        "BLOCKED",
        blocked_reason="Waiting for a document",
        resume_handler_id=owner["user"]["id"],
    )
    partner_todo = _create_task(client, partner_headers, "Partner TODO")
    partner_progress = _transition(
        client,
        partner_headers,
        _create_task(client, partner_headers, "Partner progress"),
        "IN_PROGRESS",
    )
    partner_blocked = _transition(
        client,
        partner_headers,
        _create_task(client, partner_headers, "Partner blocked"),
        "BLOCKED",
        blocked_reason="Waiting for the supplier",
        resume_handler_id=partner["user"]["id"],
    )
    review = _create_task(client, partner_headers, "Review only")
    done = _create_task(client, owner_headers, "Done only")
    cancelled = _create_task(client, partner_headers, "Cancelled only")
    deleted = _create_task(client, owner_headers, "Deleted moment task")

    with Session(db_engine) as session:
        session.get(Task, UUID(str(review["id"]))).status = TaskStatus.REVIEW
        review_row = session.get(Task, UUID(str(review["id"])))
        assert review_row is not None
        review_row.reviewer_user_id = UUID(str(owner["user"]["id"]))
        session.get(Task, UUID(str(done["id"]))).status = TaskStatus.DONE
        session.get(Task, UUID(str(cancelled["id"]))).status = TaskStatus.CANCELLED
        deleted_row = session.get(Task, UUID(str(deleted["id"])))
        assert deleted_row is not None
        deleted_row.deleted_at = datetime.now(timezone.utc)
        session.commit()

    response = client.get("/api/v1/home", headers=owner_headers)
    assert response.status_code == 200, response.text
    body = response.json()
    blocked = _moment_section(body, "blocked_tasks")
    mine = _moment_section(body, "my_tasks")
    other = _moment_section(body, "other_tasks")
    assert {item["id"] for item in blocked["items"]} == {
        owner_blocked["id"],
        partner_blocked["id"],
    }
    assert {item["id"] for item in mine["items"]} == {
        owner_todo["id"],
        owner_progress["id"],
    }
    assert {item["id"] for item in other["items"]} == {
        partner_todo["id"],
        partner_progress["id"],
    }
    groups = [blocked["items"], mine["items"], other["items"]]
    assert len({item["id"] for section in groups for item in section}) == sum(
        len(section) for section in groups
    )
    excluded = {review["id"], done["id"], cancelled["id"], deleted["id"]}
    assert excluded.isdisjoint({item["id"] for section in groups for item in section})
    assert body["moment"]["all_tasks_has_more"] is True

    partner_response = client.get("/api/v1/home", headers=partner_headers)
    assert partner_response.status_code == 200, partner_response.text
    partner_body = partner_response.json()
    assert {item["id"] for item in _moment_section(partner_body, "my_tasks")["items"]} == {
        partner_todo["id"],
        partner_progress["id"],
    }
    assert {item["id"] for item in _moment_section(partner_body, "other_tasks")["items"]} == {
        owner_todo["id"],
        owner_progress["id"],
    }


def test_home_moment_counts_pending_directions_and_current_week_live_tasks(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    owner_headers = _headers(owner)
    partner_headers = _headers(partner)
    now = datetime.now(timezone.utc)
    week_start = datetime.combine(
        now.date() - timedelta(days=now.weekday()),
        datetime.min.time(),
        tzinfo=timezone.utc,
    )
    week_end = week_start + timedelta(days=7)

    _create_task(client, owner_headers, "This week TODO", due_at=(week_start + timedelta(days=1)).isoformat())
    this_week_blocked = _create_task(
        client,
        partner_headers,
        "This week blocked",
        due_at=(week_start + timedelta(days=2)).isoformat(),
    )
    this_week_review = _create_task(
        client,
        partner_headers,
        "This week review",
        due_at=(week_start + timedelta(days=3)).isoformat(),
    )
    _create_task(client, owner_headers, "Done this week", due_at=(week_start + timedelta(days=4)).isoformat())
    _create_task(client, owner_headers, "Cancelled this week", due_at=(week_start + timedelta(days=5)).isoformat())
    _create_task(client, owner_headers, "Next week", due_at=(week_end + timedelta(days=1)).isoformat())
    deleted = _create_task(
        client,
        owner_headers,
        "Deleted this week",
        due_at=(week_start + timedelta(days=6)).isoformat(),
    )

    with Session(db_engine) as session:
        blocked_row = session.get(Task, UUID(str(this_week_blocked["id"])))
        review_row = session.get(Task, UUID(str(this_week_review["id"])))
        assert blocked_row is not None
        assert review_row is not None
        blocked_row.status = TaskStatus.BLOCKED
        review_row.status = TaskStatus.REVIEW
        review_row.reviewer_user_id = UUID(str(owner["user"]["id"]))
        for title, status in (
            ("Done this week", TaskStatus.DONE),
            ("Cancelled this week", TaskStatus.CANCELLED),
        ):
            task = session.scalar(select(Task).where(Task.title == title))
            assert task is not None
            task.status = status
        deleted_row = session.get(Task, UUID(str(deleted["id"])))
        assert deleted_row is not None
        deleted_row.deleted_at = now
        session.commit()

    incoming_source = _create_task(client, owner_headers, "Incoming count source")
    incoming = client.patch(
        f"/api/v1/tasks/{incoming_source['id']}",
        headers=partner_headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"title": "Partner proposal"},
            "base_field_versions": {"title": incoming_source["field_versions"]["title"]},
        },
    )
    assert incoming.status_code == 202, incoming.text
    outgoing_source = _create_task(client, partner_headers, "Outgoing count source")
    outgoing = client.patch(
        f"/api/v1/tasks/{outgoing_source['id']}",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"title": "Owner proposal"},
            "base_field_versions": {"title": outgoing_source["field_versions"]["title"]},
        },
    )
    assert outgoing.status_code == 202, outgoing.text

    response = client.get("/api/v1/home", headers=owner_headers)
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["needs_action_count"] == 1
    assert body["pending_approval_count"] == 1
    assert body["waiting_on_other_count"] == 1
    assert body["week_due_count"] == 3


def test_home_canonical_projection_exposes_request_directions_and_legacy_aliases(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    owner_headers = _headers(owner)
    partner_headers = _headers(partner)
    now = datetime.now(timezone.utc)
    week_start = datetime.combine(
        now.date() - timedelta(days=now.weekday()),
        datetime.min.time(),
        tzinfo=timezone.utc,
    )

    transfer_task = _create_task(
        client,
        owner_headers,
        "Incoming transfer",
        due_at=(week_start + timedelta(days=1)).isoformat(),
    )
    incoming_transfer = client.patch(
        f"/api/v1/tasks/{transfer_task['id']}",
        headers=partner_headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"current_handler_id": partner["user"]["id"]},
            "base_field_versions": {
                "current_handler_id": transfer_task["field_versions"]["current_handler_id"]
            },
        },
    )
    assert incoming_transfer.status_code == 202, incoming_transfer.text

    review_task = _create_task(
        client,
        owner_headers,
        "Outgoing review",
        due_at=(week_start + timedelta(days=2)).isoformat(),
    )
    started = _transition(client, owner_headers, review_task, "IN_PROGRESS")
    outgoing_review = _transition(client, owner_headers, started, "REVIEW")
    assert outgoing_review["status"] == "REVIEW"

    response = client.get("/api/v1/home", headers=owner_headers)
    assert response.status_code == 200, response.text
    body = response.json()

    assert body["viewer_user_id"] == owner["user"]["id"]
    as_of = datetime.fromisoformat(body["as_of"].replace("Z", "+00:00"))
    week = body["week"]
    assert week["timezone"] == "UTC"
    week_start_response = datetime.fromisoformat(week["start"].replace("Z", "+00:00"))
    week_end_response = datetime.fromisoformat(week["end"].replace("Z", "+00:00"))
    assert as_of.tzinfo is not None
    assert week_start_response.tzinfo is not None
    assert week_start_response.weekday() == 0
    assert week_start_response.time() == datetime.min.time()
    assert week_end_response - week_start_response == timedelta(days=7)
    assert week_start_response < week_end_response

    assert body["pending_approval_count"] == 1
    assert body["waiting_on_other_count"] == 1
    assert body["entry_counts"] == {
        "needs_me": body["pending_approval_count"],
        "waiting_on_other": body["waiting_on_other_count"],
        "due_this_week": body["week_due_count"],
    }

    moment = body["moment"]
    assert moment["blocked"] == moment["blocked_tasks"]
    assert moment["mine"] == moment["my_tasks"]
    assert moment["other"] == moment["other_tasks"]

    needs_me = body["entries"]["needs_me"]
    waiting_on_other = body["entries"]["waiting_on_other"]
    due_this_week = body["entries"]["due_this_week"]
    assert needs_me["has_more"] is False
    assert waiting_on_other["has_more"] is False
    assert due_this_week["has_more"] is False
    assert needs_me["items"][0]["approval_request"]["id"] == incoming_transfer.json()["approval_request"]["id"]
    assert needs_me["items"][0]["approval_request"]["request_type"] == "HANDLER_TRANSFER"
    assert needs_me["items"][0]["task"]["id"] == transfer_task["id"]
    assert waiting_on_other["items"][0]["approval_request"]["request_type"] == "STATUS_UPDATE"
    assert waiting_on_other["items"][0]["task"]["id"] == review_task["id"]
    assert {item["id"] for item in due_this_week["items"]} == {
        transfer_task["id"],
        review_task["id"],
    }


def test_home_canonical_entries_include_taskless_requests_and_filter_deleted_targets(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    owner_headers = _headers(owner)
    partner_headers = _headers(partner)

    incoming_task = _create_task(client, owner_headers, "Deleted approval target")
    deleted_pending = client.patch(
        f"/api/v1/tasks/{incoming_task['id']}",
        headers=partner_headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"title": "Deleted proposal"},
            "base_field_versions": {"title": incoming_task["field_versions"]["title"]},
        },
    )
    assert deleted_pending.status_code == 202, deleted_pending.text

    for index in range(6):
        pending = client.post(
            "/api/v1/workspaces/current/classifications",
            headers=partner_headers,
            json={"request_id": str(uuid4()), "name": f"对方{index}"},
        )
        assert pending.status_code == 202, pending.text

    outgoing_taskless = client.post(
        "/api/v1/workspaces/current/classifications",
        headers=owner_headers,
        json={"request_id": str(uuid4()), "name": "本人类"},
    )
    assert outgoing_taskless.status_code == 202, outgoing_taskless.text

    with Session(db_engine) as session:
        deleted_row = session.get(Task, UUID(str(incoming_task["id"])))
        assert deleted_row is not None
        deleted_row.deleted_at = datetime.now(timezone.utc)
        session.commit()

    response = client.get("/api/v1/home", headers=owner_headers)
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["pending_approval_count"] == 6
    assert body["waiting_on_other_count"] == 1
    assert body["entry_counts"] == {
        "needs_me": 6,
        "waiting_on_other": 1,
        "due_this_week": body["week_due_count"],
    }

    needs_me = body["entries"]["needs_me"]
    waiting_on_other = body["entries"]["waiting_on_other"]
    assert len(needs_me["items"]) == 5
    assert needs_me["has_more"] is True
    assert all(item["approval_request"]["task_id"] is None for item in needs_me["items"])
    assert all(item["task"] is None for item in needs_me["items"])
    assert waiting_on_other["has_more"] is False
    assert waiting_on_other["items"][0]["approval_request"]["task_id"] is None
    assert waiting_on_other["items"][0]["task"] is None
    assert incoming_task["id"] not in {
        item["task"]["id"]
        for section in (needs_me, waiting_on_other)
        for item in section["items"]
        if item["task"] is not None
    }


def test_home_entry_page_paginates_taskless_approvals_without_duplicates(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    owner_headers = _headers(owner)
    partner_headers = _headers(partner)

    expected_request_ids: list[str] = []
    for index in range(5):
        pending = client.post(
            "/api/v1/workspaces/current/classifications",
            headers=partner_headers,
            json={"request_id": str(uuid4()), "name": f"乙{index}"},
        )
        assert pending.status_code == 202, pending.text
        expected_request_ids.append(pending.json()["approval_request"]["id"])

    # Keep a pending task approval in the owner's workspace, then move only
    # its task to another workspace. The request remains in the database but
    # must not affect either the count or the returned pages.
    foreign_task = _create_task(client, owner_headers, "Foreign approval target")
    foreign_pending = client.patch(
        f"/api/v1/tasks/{foreign_task['id']}",
        headers=partner_headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"title": "Foreign proposal"},
            "base_field_versions": {"title": foreign_task["field_versions"]["title"]},
        },
    )
    assert foreign_pending.status_code == 202, foreign_pending.text
    with Session(db_engine) as session:
        foreign_workspace = Workspace(name="Entry page foreign")
        session.add(foreign_workspace)
        session.flush()
        foreign_row = session.get(Task, UUID(str(foreign_task["id"])))
        assert foreign_row is not None
        foreign_row.workspace_id = foreign_workspace.id
        session.commit()

    first = client.get(
        "/api/v1/home/entries/needs_me?limit=2",
        headers=owner_headers,
    )
    assert first.status_code == 200, first.text
    first_body = first.json()
    assert first_body["count"] == 5
    assert len(first_body["items"]) == 2
    assert first_body["has_more"] is True
    assert isinstance(first_body["next_cursor"], str)
    assert first_body["next_cursor"].startswith("home-entry-v1.")
    assert all(item["task"] is None for item in first_body["items"])

    second = client.get(
        "/api/v1/home/entries/needs_me?limit=2&after_cursor="
        + first_body["next_cursor"],
        headers=owner_headers,
    )
    assert second.status_code == 200, second.text
    second_body = second.json()
    assert second_body["count"] == 5
    assert len(second_body["items"]) == 2
    assert second_body["has_more"] is True

    # Reusing a cursor is deterministic while the underlying list is stable.
    replay = client.get(
        "/api/v1/home/entries/needs_me?limit=2&after_cursor="
        + first_body["next_cursor"],
        headers=owner_headers,
    )
    assert replay.status_code == 200, replay.text
    assert replay.json()["items"] == second_body["items"]

    third = client.get(
        "/api/v1/home/entries/needs_me?limit=2&after_cursor="
        + second_body["next_cursor"],
        headers=owner_headers,
    )
    assert third.status_code == 200, third.text
    third_body = third.json()
    assert third_body["count"] == 5
    assert len(third_body["items"]) == 1
    assert third_body["has_more"] is False
    assert third_body["next_cursor"] is None

    page_ids = [
        item["approval_request"]["id"]
        for body in (first_body, second_body, third_body)
        for item in body["items"]
    ]
    assert len(page_ids) == len(set(page_ids)) == 5
    assert set(page_ids) == set(expected_request_ids)

    home = client.get("/api/v1/home", headers=owner_headers)
    assert home.status_code == 200, home.text
    assert home.json()["entry_counts"]["needs_me"] == first_body["count"]


def test_home_entry_page_paginates_due_tasks_with_stable_ordering(db_engine) -> None:
    client = _client(db_engine)
    owner, _partner = _ready_workspace(client)
    headers = _headers(owner)
    now = datetime.now(timezone.utc)
    week_start = datetime.combine(
        now.date() - timedelta(days=now.weekday()),
        datetime.min.time(),
        tzinfo=timezone.utc,
    )
    due_at = week_start + timedelta(days=1)
    tasks = [
        _create_task(client, headers, f"Due page {index}", due_at=due_at.isoformat())
        for index in range(5)
    ]
    expected_ids = sorted(task["id"] for task in tasks)

    # Force all non-date ordering columns to tie so the id tie-breaker and
    # keyset predicate are exercised across page boundaries.
    with Session(db_engine) as session:
        updated_at = datetime(2030, 1, 1, tzinfo=timezone.utc)
        for task in tasks:
            row = session.get(Task, UUID(str(task["id"])))
            assert row is not None
            row.updated_at = updated_at
        session.commit()

    first = client.get(
        "/api/v1/home/entries/due_this_week?limit=2",
        headers=headers,
    )
    assert first.status_code == 200, first.text
    first_body = first.json()
    assert first_body["count"] == 5
    assert [item["id"] for item in first_body["items"]] == expected_ids[:2]
    assert first_body["has_more"] is True
    assert first_body["next_cursor"]

    second = client.get(
        "/api/v1/home/entries/due_this_week?limit=2&after_cursor="
        + first_body["next_cursor"],
        headers=headers,
    )
    assert second.status_code == 200, second.text
    second_body = second.json()
    assert second_body["count"] == 5
    assert [item["id"] for item in second_body["items"]] == expected_ids[2:4]
    assert second_body["has_more"] is True

    third = client.get(
        "/api/v1/home/entries/due_this_week?limit=2&after_cursor="
        + second_body["next_cursor"],
        headers=headers,
    )
    assert third.status_code == 200, third.text
    third_body = third.json()
    assert third_body["count"] == 5
    assert [item["id"] for item in third_body["items"]] == expected_ids[4:]
    assert third_body["has_more"] is False
    assert third_body["next_cursor"] is None

    home = client.get("/api/v1/home", headers=headers)
    assert home.status_code == 200, home.text
    assert home.json()["entry_counts"]["due_this_week"] == first_body["count"]


def test_home_entry_page_rejects_invalid_entry_limit_and_cursor(db_engine) -> None:
    client = _client(db_engine)
    owner, _partner = _ready_workspace(client)
    headers = _headers(owner)

    invalid_entry = client.get("/api/v1/home/entries/not-an-entry", headers=headers)
    assert invalid_entry.status_code == 422, invalid_entry.text
    assert invalid_entry.json()["code"] == "VALIDATION_ERROR"

    for limit in ("0", "-1", "501"):
        response = client.get(
            f"/api/v1/home/entries/needs_me?limit={limit}",
            headers=headers,
        )
        assert response.status_code == 422, response.text

    invalid_cursor = client.get(
        "/api/v1/home/entries/needs_me?after_cursor=not-a-home-cursor",
        headers=headers,
    )
    assert invalid_cursor.status_code == 422, invalid_cursor.text
    assert invalid_cursor.json()["code"] == "invalid_home_cursor"

    initial = client.get(
        "/api/v1/home/entries/needs_me?limit=1",
        headers=headers,
    )
    assert initial.status_code == 200, initial.text
    if initial.json()["next_cursor"] is not None:
        wrong_entry = client.get(
            "/api/v1/home/entries/waiting_on_other?after_cursor="
            + initial.json()["next_cursor"],
            headers=headers,
        )
        assert wrong_entry.status_code == 422, wrong_entry.text
        assert wrong_entry.json()["code"] == "invalid_home_cursor"


def test_home_canonical_moment_sections_are_bounded_and_disjoint(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    owner_headers = _headers(owner)
    partner_headers = _headers(partner)

    mine_tasks = [
        _create_task(client, owner_headers, f"Mine moment {index}")
        for index in range(6)
    ]
    other_tasks = [
        _create_task(client, partner_headers, f"Other moment {index}")
        for index in range(6)
    ]
    blocked_tasks = [
        _transition(
            client,
            owner_headers,
            _create_task(client, owner_headers, f"Blocked moment {index}"),
            "BLOCKED",
            blocked_reason=f"Blocked reason {index}",
            resume_handler_id=owner["user"]["id"],
        )
        for index in range(4)
    ]

    response = client.get("/api/v1/home", headers=owner_headers)
    assert response.status_code == 200, response.text
    moment = response.json()["moment"]

    canonical = {
        "blocked": moment["blocked"],
        "mine": moment["mine"],
        "other": moment["other"],
    }
    expected_ids = {
        "blocked": {task["id"] for task in blocked_tasks},
        "mine": {task["id"] for task in mine_tasks},
        "other": {task["id"] for task in other_tasks},
    }
    limits = {"blocked": 3, "mine": 5, "other": 5}
    canonical_ids: list[str] = []
    for name, section in canonical.items():
        items = section["items"]
        assert len(items) == limits[name]
        assert section["has_more"] is True
        ids = [item["id"] for item in items]
        assert set(ids) <= expected_ids[name]
        canonical_ids.extend(ids)

        legacy_items = moment[{
            "blocked": "blocked_tasks",
            "mine": "my_tasks",
            "other": "other_tasks",
        }[name]]["items"]
        assert [item["id"] for item in legacy_items[: limits[name]]] == ids
        assert len(legacy_items) == len(expected_ids[name])

    assert len(canonical_ids) == len(set(canonical_ids))
    assert moment["all_tasks_has_more"] is True
    assert moment["blocked_tasks"]["has_more"] is False
    assert moment["my_tasks"]["has_more"] is False
    assert moment["other_tasks"]["has_more"] is False
