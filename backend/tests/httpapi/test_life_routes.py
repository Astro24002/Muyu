from __future__ import annotations

from datetime import date, datetime, timezone
from uuid import uuid4

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.db.models import ActivityEvent, HabitCheckin, Task, WorkspaceChangeLog
from app.life.anniversaries import next_occurrence
from app.life.checkins import period_key

from .test_home_routes import _client, _headers, _ready_workspace


def test_ledger_amount_summary_filter_delete_and_replay(db_engine) -> None:
    client = _client(db_engine)
    first, second = _ready_workspace(client)
    headers = _headers(first)
    payload = {
        "request_id": str(uuid4()),
        "type": "EXPENSE",
        "amount": "12.34",
        "title": "早餐",
        "category": "餐饮",
        "payer_or_payee_id": second["user"]["id"],
        "date": "2026-09-17",
    }
    created = client.post("/api/v1/ledger", headers=headers, json=payload)
    assert created.status_code == 201, created.text
    entry = created.json()
    assert entry["amount_minor"] == 1234
    assert entry["payer_or_payee_id"] == second["user"]["id"]
    assert entry["created_by"] == first["user"]["id"]
    replay = client.post("/api/v1/ledger", headers=headers, json=payload)
    assert replay.status_code == 201, replay.text
    assert replay.json()["id"] == entry["id"]
    assert replay.json()["cursor"] == entry["cursor"]

    changed = client.patch(
        f"/api/v1/ledger/{entry['id']}",
        headers=_headers(second),
        json={"request_id": str(uuid4()), "expected_version": 1, "changes": {"amount": "8.50"}},
    )
    assert changed.status_code == 200, changed.text
    assert changed.json()["amount_minor"] == 850
    assert changed.json()["updated_by"] == second["user"]["id"]
    assert client.patch(
        f"/api/v1/ledger/{entry['id']}",
        headers=headers,
        json={"request_id": str(uuid4()), "expected_version": 1, "changes": {"title": "旧版本"}},
    ).status_code == 409
    assert client.post("/api/v1/ledger", headers=headers, json=payload | {"request_id": str(uuid4()), "amount": "0.001"}).status_code == 422
    assert client.get("/api/v1/ledger", headers=headers, params={"month": "2026-09", "type": "INCOME"}).json()["items"] == []
    summary = client.get("/api/v1/ledger/summary", headers=headers, params={"month": "2026-09"}).json()
    assert summary["expense_minor"] == 850
    assert summary["balance_minor"] == -850
    assert summary["categories"][0]["amount_minor"] == 850

    deleted = client.request(
        "DELETE", f"/api/v1/ledger/{entry['id']}", headers=headers,
        json={"request_id": str(uuid4()), "expected_version": 2, "confirm": True},
    )
    assert deleted.status_code == 200, deleted.text
    assert client.get("/api/v1/ledger/summary", headers=headers, params={"month": "2026-09"}).json()["expense_minor"] == 0
    changes = client.get("/api/v1/workspaces/current/changes", headers=headers, params={"after_cursor": entry["cursor"] - 1}).json()["changes"]
    assert any(row["resource_type"] == "ledger_entry" and row["action"] == "DELETED" for row in changes)


def test_habit_owner_period_replay_and_history(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    created = client.post(
        "/api/v1/habits", headers=_headers(owner),
        json={"request_id": str(uuid4()), "title": "阅读", "frequency": "DAILY", "start_date": "2026-01-01"},
    )
    assert created.status_code == 201, created.text
    habit = created.json()
    assert client.get("/api/v1/habits?owner=other", headers=_headers(partner)).json()["items"][0]["id"] == habit["id"]
    assert client.post(
        f"/api/v1/habits/{habit['id']}/checkin", headers=_headers(partner),
        json={"request_id": str(uuid4()), "expected_version": 1},
    ).status_code == 403
    action = {"request_id": str(uuid4()), "expected_version": 1}
    first = client.post(f"/api/v1/habits/{habit['id']}/checkin", headers=_headers(owner), json=action)
    assert first.status_code == 200, first.text
    again = client.post(f"/api/v1/habits/{habit['id']}/checkin", headers=_headers(owner), json=action)
    assert again.status_code == 200, again.text
    assert again.json()["checkin"]["id"] == first.json()["checkin"]["id"]
    repeated = client.post(f"/api/v1/habits/{habit['id']}/checkin", headers=_headers(owner), json={"request_id": str(uuid4()), "expected_version": 1})
    assert repeated.status_code == 200, repeated.text
    assert repeated.json()["checkin"]["id"] == first.json()["checkin"]["id"]
    undo = client.post(f"/api/v1/habits/{habit['id']}/undo", headers=_headers(owner), json={"request_id": str(uuid4()), "expected_version": 1})
    assert undo.status_code == 200, undo.text
    assert undo.json()["checked_in"] is False
    assert len(undo.json()["checkins"]) == 1
    paused = client.post(f"/api/v1/habits/{habit['id']}/pause", headers=_headers(owner), json={"request_id": str(uuid4()), "expected_version": 1})
    assert paused.status_code == 200, paused.text
    assert client.post(f"/api/v1/habits/{habit['id']}/checkin", headers=_headers(owner), json={"request_id": str(uuid4()), "expected_version": 2}).status_code == 409
    resumed = client.post(f"/api/v1/habits/{habit['id']}/resume", headers=_headers(owner), json={"request_id": str(uuid4()), "expected_version": 2})
    assert resumed.status_code == 200, resumed.text
    changed = client.patch(f"/api/v1/habits/{habit['id']}", headers=_headers(owner), json={"request_id": str(uuid4()), "expected_version": 3, "changes": {"frequency": "WEEKLY"}})
    assert changed.status_code == 200, changed.text
    assert changed.json()["checkins"][0]["frequency_snapshot"] == "DAILY"

    with Session(db_engine) as session:
        assert session.scalar(select(func.count(HabitCheckin.id)).where(HabitCheckin.habit_id == habit["id"], HabitCheckin.revoked_at.is_(None))) == 0


def test_paused_habit_can_be_edited_but_not_checked_in(db_engine) -> None:
    client = _client(db_engine)
    owner, _ = _ready_workspace(client)
    headers = _headers(owner)
    habit = client.post(
        "/api/v1/habits", headers=headers,
        json={"request_id": str(uuid4()), "title": "阅读", "frequency": "DAILY", "start_date": "2026-01-01"},
    ).json()
    paused = client.post(
        f"/api/v1/habits/{habit['id']}/pause", headers=headers,
        json={"request_id": str(uuid4()), "expected_version": 1},
    )
    assert paused.status_code == 200
    edited = client.patch(
        f"/api/v1/habits/{habit['id']}", headers=headers,
        json={"request_id": str(uuid4()), "expected_version": 2, "changes": {"title": "每天阅读"}},
    )
    assert edited.status_code == 200, edited.text
    assert edited.json()["status"] == "PAUSED"
    assert edited.json()["title"] == "每天阅读"
    assert client.post(
        f"/api/v1/habits/{habit['id']}/checkin", headers=headers,
        json={"request_id": str(uuid4()), "expected_version": 3},
    ).status_code == 409


def test_anniversary_future_leap_day_and_preparation_uniqueness(db_engine) -> None:
    assert next_occurrence(date(2028, 6, 1), date(2026, 9, 17)) == date(2028, 6, 1)
    assert next_occurrence(date(2024, 2, 29), date(2026, 2, 1)) == date(2026, 2, 28)
    assert next_occurrence(date(2024, 2, 29), date(2028, 2, 28)) == date(2028, 2, 29)
    assert period_key(date(2026, 9, 20), "WEEKLY") == "2026-09-14"
    assert period_key(date(2026, 9, 21), "WEEKLY") == "2026-09-21"

    client = _client(db_engine)
    first, second = _ready_workspace(client)
    created = client.post(
        "/api/v1/anniversaries", headers=_headers(first),
        json={"request_id": str(uuid4()), "title": "认识纪念日", "anchor_date": "2020-10-01", "kind": "ANNIVERSARY", "prepare_days": 7},
    )
    assert created.status_code == 201, created.text
    anniversary = created.json()
    first_prepare = client.post(f"/api/v1/anniversaries/{anniversary['id']}/prepare", headers=_headers(first), json={"request_id": str(uuid4())})
    assert first_prepare.status_code == 200, first_prepare.text
    task = first_prepare.json()["task"]
    assert task["current_handler_id"] == first["user"]["id"]
    assert task["status"] == "IN_PROGRESS"
    assert task["source_key"].startswith(f"anniversary:{anniversary['id']}:")
    second_prepare = client.post(f"/api/v1/anniversaries/{anniversary['id']}/prepare", headers=_headers(second), json={"request_id": str(uuid4())})
    assert second_prepare.status_code == 200, second_prepare.text
    assert second_prepare.json()["task"]["id"] == task["id"]
    assert client.request("DELETE", f"/api/v1/anniversaries/{anniversary['id']}", headers=_headers(second), json={"request_id": str(uuid4()), "expected_version": 1, "confirm": True}).status_code == 200
    assert client.get(f"/api/v1/tasks/{task['id']}", headers=_headers(first)).status_code == 200
    with Session(db_engine) as session:
        assert session.scalar(select(func.count(Task.id)).where(Task.source_key == task["source_key"])) == 1
        assert session.scalar(select(func.count(ActivityEvent.id)).where(ActivityEvent.event_type == "ANNIVERSARY_PREPARATION_TASK_GENERATED")) == 1
