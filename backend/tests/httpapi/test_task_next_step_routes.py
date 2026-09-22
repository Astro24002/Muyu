from __future__ import annotations

from uuid import uuid4

from fastapi.testclient import TestClient
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from .test_home_routes import _client, _headers, _ready_workspace
from app.db.models import Task, TaskApprovalRequest, WorkspaceChangeLog


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


def test_acceptance_criteria_is_a_separate_versioned_agreement(db_engine) -> None:
    client = _client(db_engine)
    owner, _ = _ready_workspace(client)
    headers = _headers(owner) | {"X-Muyu-Client-Contract": "2026-09-v1"}
    created = client.post("/api/v1/tasks", headers=headers, json={
        "request_id": str(uuid4()), "title": "整理清单", "quadrant": "Q2",
        "labels": ["工作"], "next_step_text": "列出候选项",
        "acceptance_criteria": "双方确认清单内容和截止日期。",
    })
    assert created.status_code == 201, created.text
    task = created.json()
    assert task["acceptance_criteria"] == "双方确认清单内容和截止日期。"
    assert task["review_submitted_at"] is None

    updated = client.patch(f"/api/v1/tasks/{task['id']}", headers=headers, json={
        "request_id": str(uuid4()),
        "changes": {"acceptance_criteria": "双方确认清单及负责人。"},
        "base_field_versions": {"acceptance_criteria": task["field_versions"]["acceptance_criteria"]},
    })
    assert updated.status_code == 200, updated.text
    assert updated.json()["acceptance_criteria"] == "双方确认清单及负责人。"
    assert client.get(f"/api/v1/tasks/{task['id']}", headers=headers).json()["acceptance_criteria"] == "双方确认清单及负责人。"


def test_acceptance_criteria_rejects_blank_and_overlong(db_engine) -> None:
    client = _client(db_engine)
    owner, _ = _ready_workspace(client)
    headers = _headers(owner)
    for value in ("   ", "字" * 501):
        response = client.post("/api/v1/tasks", headers=headers, json={
            "request_id": str(uuid4()), "title": "边界任务", "quadrant": "Q2",
            "labels": ["工作"], "acceptance_criteria": value,
        })
        assert response.status_code == 422, response.text
        assert response.json()["code"] == "invalid_request"


def test_non_owner_acceptance_criteria_change_waits_for_approval(db_engine) -> None:
    client = _client(db_engine)
    owner, other = _ready_workspace(client)
    owner_headers = _headers(owner)
    other_headers = _headers(other)
    created = client.post("/api/v1/tasks", headers=owner_headers, json={
        "request_id": str(uuid4()), "title": "商定验收", "quadrant": "Q2",
        "labels": ["工作"], "acceptance_criteria": "确认第一版",
    })
    assert created.status_code == 201, created.text
    task = created.json()
    proposal = client.patch(f"/api/v1/tasks/{task['id']}", headers=other_headers, json={
        "request_id": str(uuid4()), "changes": {"acceptance_criteria": "确认第二版"},
        "base_field_versions": {"acceptance_criteria": task["field_versions"]["acceptance_criteria"]},
    })
    assert proposal.status_code == 202, proposal.text
    assert proposal.json()["approval_request"]["request_type"] == "TASK_UPDATE"
    assert client.get(f"/api/v1/tasks/{task['id']}", headers=other_headers).json()["acceptance_criteria"] == "确认第一版"
    approved = client.post(
        f"/api/v1/workspaces/{task['workspace_id']}/approval-requests/{proposal.json()['approval_request']['id']}/approve",
        headers=owner_headers, json={"request_id": str(uuid4())},
    )
    assert approved.status_code == 200, approved.text
    assert approved.json()["task"]["acceptance_criteria"] == "确认第二版"


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


def test_v1_create_contract_boundaries(db_engine) -> None:
    client = _client(db_engine)
    owner, _ = _ready_workspace(client)
    headers = _headers(owner) | {"X-Muyu-Client-Contract": "2026-09-v1"}
    for fields in ({}, {"next_step_text": None}, {"next_step_text": ""}, {"next_step_text": " \t "}):
        response = client.post("/api/v1/tasks", headers=headers, json={
            "request_id": str(uuid4()), "title": "契约任务", "quadrant": "Q2",
            "labels": ["工作"], **fields,
        })
        assert response.status_code == 422, response.text
        assert response.json()["code"] == "next_step_required"
    assert client.get("/api/v1/tasks", headers=headers).json() == []
    response = client.post("/api/v1/tasks", headers=headers, json={
        "request_id": str(uuid4()), "title": "契约任务", "quadrant": "Q2",
        "labels": ["工作"], "next_step_text": "确认时间",
    })
    assert response.status_code == 201, response.text
    assert response.json()["next_step_text"] == "确认时间"


def test_unknown_contract_is_rejected_on_non_task_api() -> None:
    from app.main import create_app
    client = TestClient(create_app())
    response = client.post("/api/v1/web-login/challenges", headers={
        "X-Muyu-Client-Contract": "future-version",
    }, json={})
    assert response.status_code == 400, response.text
    assert response.json()["code"] == "unsupported_client_contract"


def test_contract_cors_preflight() -> None:
    from app.main import create_app
    response = TestClient(create_app()).options("/api/v1/tasks", headers={
        "Origin": "http://localhost:5173",
        "Access-Control-Request-Method": "POST",
        "Access-Control-Request-Headers": "content-type,x-muyu-client-contract",
    })
    assert response.status_code == 200
    assert "x-muyu-client-contract" in response.headers["access-control-allow-headers"].lower()


def test_v1_create_for_ta_is_atomic_transfer_request(db_engine) -> None:
    client = _client(db_engine)
    owner, other = _ready_workspace(client)
    headers = _headers(owner) | {"X-Muyu-Client-Contract": "2026-09-v1"}
    response = client.post("/api/v1/tasks", headers=headers, json={
        "request_id": str(uuid4()), "title": "交给 TA", "quadrant": "Q2",
        "labels": ["工作"], "next_step_text": "确认交付时间",
        "target_handler_id": other["user"]["id"],
    })
    assert response.status_code == 201, response.text
    payload = response.json()
    assert payload["status"] == "IN_PROGRESS"
    assert payload["current_handler_id"] == owner["user"]["id"]
    assert payload["approval_request"]["request_type"] == "HANDLER_TRANSFER"
    assert payload["approval_request"]["proposed_changes"]["proposed_next_step"] == "确认交付时间"

    with Session(db_engine) as session:
        approval = session.scalar(
            select(TaskApprovalRequest).where(
                TaskApprovalRequest.id == payload["approval_request"]["id"],
            )
        )
        assert approval is not None
        cursors = session.scalars(
            select(WorkspaceChangeLog.cursor)
            .where(WorkspaceChangeLog.workspace_id == approval.workspace_id)
            .order_by(WorkspaceChangeLog.cursor.asc())
        ).all()
        assert payload["cursor"] == max(cursors)


def test_v1_create_for_ta_reuses_only_identical_target_and_rolls_back_invalid_target(db_engine) -> None:
    client = _client(db_engine)
    owner, other = _ready_workspace(client)
    headers = _headers(owner) | {"X-Muyu-Client-Contract": "2026-09-v1"}
    request_id = str(uuid4())
    payload = {
        "request_id": request_id,
        "title": "幂等交接",
        "quadrant": "Q2",
        "labels": ["工作"],
        "next_step_text": "确认交付时间",
        "target_handler_id": other["user"]["id"],
    }
    first = client.post("/api/v1/tasks", headers=headers, json=payload)
    assert first.status_code == 201, first.text
    replay = client.post("/api/v1/tasks", headers=headers, json=payload)
    assert replay.status_code == 201, replay.text
    assert replay.json()["id"] == first.json()["id"]
    changed = dict(payload)
    changed["target_handler_id"] = str(uuid4())
    changed["next_step_text"] = "不应覆盖原请求"
    conflict = client.post("/api/v1/tasks", headers=headers, json=changed)
    assert conflict.status_code == 409, conflict.text
    assert conflict.json()["code"] == "idempotency_key_reused"

    invalid = client.post("/api/v1/tasks", headers=headers, json={
        **payload,
        "request_id": str(uuid4()),
        "target_handler_id": str(uuid4()),
    })
    assert invalid.status_code in {400, 409, 422}, invalid.text
    with Session(db_engine) as session:
        assert session.scalar(select(func.count()).select_from(Task).where(Task.title == "幂等交接")) == 1
