from __future__ import annotations

from uuid import uuid4

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.enums import TaskApprovalRequestStatus
from app.db.models import Task, TaskApprovalRequest

from .test_home_routes import _client, _headers, _ready_workspace


def _task(client, headers, *, criteria: str = "双方确认结果") -> dict[str, object]:
    response = client.post("/api/v1/tasks", headers=headers, json={
        "request_id": str(uuid4()),
        "title": "协议任务",
        "quadrant": "Q2",
        "labels": ["工作"],
        "acceptance_criteria": criteria,
    })
    assert response.status_code == 201, response.text
    return response.json()


def test_agreement_update_keeps_current_criteria_until_approval(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    task = _task(client, _headers(owner))
    response = client.post(
        f"/api/v1/tasks/{task['id']}/agreement-requests",
        headers=_headers(partner),
        json={
            "request_id": str(uuid4()),
            "acceptance_criteria": "双方确认第二版结果",
            "base_field_version": task["field_versions"]["acceptance_criteria"],
        },
    )
    assert response.status_code == 202, response.text
    approval = response.json()["approval_request"]
    assert approval["request_type"] == "TASK_UPDATE"
    assert approval["proposed_changes"]["agreement_update"] is True
    assert client.get(f"/api/v1/tasks/{task['id']}", headers=_headers(owner)).json()["acceptance_criteria"] == "双方确认结果"

    duplicate = client.post(
        f"/api/v1/tasks/{task['id']}/agreement-requests",
        headers=_headers(partner),
        json={
            "request_id": str(uuid4()),
            "acceptance_criteria": "另一份约定",
            "base_field_version": task["field_versions"]["acceptance_criteria"],
        },
    )
    assert duplicate.status_code == 409
    assert duplicate.json()["code"] == "approval_already_pending"

    approved = client.post(
        f"/api/v1/workspaces/{task['workspace_id']}/approval-requests/{approval['id']}/approve",
        headers=_headers(owner),
        json={"request_id": str(uuid4())},
    )
    assert approved.status_code == 200, approved.text
    assert approved.json()["task"]["acceptance_criteria"] == "双方确认第二版结果"


def test_agreement_update_conflicts_if_criteria_changed_while_pending(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    owner_headers = _headers(owner)
    task = _task(client, owner_headers)
    pending = client.post(
        f"/api/v1/tasks/{task['id']}/agreement-requests",
        headers=_headers(partner),
        json={
            "request_id": str(uuid4()),
            "acceptance_criteria": "对方提出的版本",
            "base_field_version": task["field_versions"]["acceptance_criteria"],
        },
    ).json()["approval_request"]
    changed = client.patch(
        f"/api/v1/tasks/{task['id']}",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"acceptance_criteria": "负责人已更新的版本"},
            "base_field_versions": {"acceptance_criteria": task["field_versions"]["acceptance_criteria"]},
        },
    )
    assert changed.status_code == 200, changed.text
    conflict = client.post(
        f"/api/v1/workspaces/{task['workspace_id']}/approval-requests/{pending['id']}/approve",
        headers=owner_headers,
        json={"request_id": str(uuid4())},
    )
    assert conflict.status_code == 409
    assert conflict.json()["code"] == "approval_conflicted"
    with Session(db_engine) as session:
        row = session.get(TaskApprovalRequest, pending["id"])
        assert row is not None
        assert row.status == TaskApprovalRequestStatus.CONFLICTED
        current = session.get(Task, task["id"])
        assert current is not None
        assert current.acceptance_criteria == "负责人已更新的版本"


def test_cancellation_request_requires_approval_and_preserves_task_until_then(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    task = _task(client, _headers(owner))
    response = client.post(
        f"/api/v1/tasks/{task['id']}/cancellation-requests",
        headers=_headers(partner),
        json={
            "request_id": str(uuid4()),
            "reason": "当前目标已经改变",
            "base_lifecycle_version": task["lifecycle_version"],
        },
    )
    assert response.status_code == 202, response.text
    approval = response.json()["approval_request"]
    assert approval["request_type"] == "TASK_DELETE"
    assert client.get("/api/v1/tasks", headers=_headers(owner)).json()[0]["id"] == task["id"]

    rejected = client.post(
        f"/api/v1/workspaces/{task['workspace_id']}/approval-requests/{approval['id']}/reject",
        headers=_headers(owner),
        json={"request_id": str(uuid4()), "reason": "仍需保留"},
    )
    assert rejected.status_code == 200, rejected.text
    assert client.get("/api/v1/tasks", headers=_headers(owner)).json()[0]["id"] == task["id"]

    second = client.post(
        f"/api/v1/tasks/{task['id']}/cancellation-requests",
        headers=_headers(partner),
        json={
            "request_id": str(uuid4()),
            "reason": "双方确认不再继续",
            "base_lifecycle_version": task["lifecycle_version"],
        },
    ).json()["approval_request"]
    approved = client.post(
        f"/api/v1/workspaces/{task['workspace_id']}/approval-requests/{second['id']}/approve",
        headers=_headers(owner),
        json={"request_id": str(uuid4())},
    )
    assert approved.status_code == 200, approved.text
    assert approved.json()["task"]["deleted_at"] is not None
    assert client.get("/api/v1/tasks", headers=_headers(owner)).json() == []

