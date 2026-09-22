from __future__ import annotations

from uuid import uuid4

from fastapi.testclient import TestClient
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.db.models import ActivityEvent, Task, TaskOperation, TaskStatusHistory, WorkspaceChangeLog, WorkspaceCursor
from app.main import create_app
from app.tasks.service import TaskService

from .test_device_readonly_permissions import _headers, _ready_workspace
from .test_lightweight_routes import FakeSmsProvider


def _client(db_engine) -> TestClient:
    app = create_app()
    app.state.engine = db_engine
    app.state.ready = True
    app.state.sms_provider = FakeSmsProvider()
    return TestClient(app)


def _side_effect_counts(db_engine, workspace_id: str, task_id: str) -> tuple[int, int, int, int, int]:
    with Session(db_engine) as session:
        return (
            session.scalar(
                select(func.count()).select_from(TaskOperation).where(TaskOperation.task_id == task_id)
            ),
            session.scalar(
                select(func.count()).select_from(ActivityEvent).where(ActivityEvent.task_id == task_id)
            ),
            session.scalar(
                select(func.count()).select_from(TaskStatusHistory).where(TaskStatusHistory.task_id == task_id)
            ),
            session.scalar(
                select(func.count())
                .select_from(WorkspaceChangeLog)
                .where(WorkspaceChangeLog.workspace_id == workspace_id)
            ),
            session.scalar(
                select(WorkspaceCursor.next_cursor).where(WorkspaceCursor.workspace_id == workspace_id)
            ),
        )


def test_non_owner_patch_creates_pending_approval_and_owner_can_apply(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    owner_headers = _headers(owner)
    partner_headers = _headers(partner)
    created = client.post(
        "/api/v1/tasks",
        headers=owner_headers,
        json={"request_id": str(uuid4()), "title": "Original", "quadrant": "Q2", "labels": ["工作"]},
    )
    assert created.status_code == 201, created.text
    task = created.json()

    pending = client.patch(
        f"/api/v1/tasks/{task['id']}",
        headers=partner_headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"title": "Partner proposal"},
            "base_field_versions": {"title": task["field_versions"]["title"]},
        },
    )
    assert pending.status_code == 202, pending.text
    approval = pending.json()["approval_request"]
    assert pending.json()["pending"] is True
    assert approval["requester_id"] == partner["user"]["id"]
    assert approval["approver_id"] == owner["user"]["id"]

    incoming = client.get(
        f"/api/v1/workspaces/{task['workspace_id']}/approval-requests?box=incoming",
        headers=owner_headers,
    )
    assert incoming.status_code == 200, incoming.text
    assert incoming.json()[0]["id"] == approval["id"]

    approved = client.post(
        f"/api/v1/workspaces/{task['workspace_id']}/approval-requests/{approval['id']}/approve",
        headers=owner_headers,
        json={"request_id": str(uuid4())},
    )
    assert approved.status_code == 200, approved.text
    assert approved.json()["approval_request"]["status"] == "APPROVED"
    assert approved.json()["task"]["title"] == "Partner proposal"


def test_owner_handler_patch_requires_partner_approval_and_replays_idempotently(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    owner_headers = _headers(owner)
    partner_headers = _headers(partner)
    created = client.post(
        "/api/v1/tasks",
        headers=owner_headers,
        json={"request_id": str(uuid4()), "title": "Owner transfer", "quadrant": "Q1", "labels": ["工作"]},
    )
    assert created.status_code == 201, created.text
    task = created.json()
    request_id = str(uuid4())
    body = {
        "request_id": request_id,
        "changes": {"current_handler_id": partner["user"]["id"]},
        "base_field_versions": {"current_handler_id": task["field_versions"]["current_handler_id"]},
    }

    pending = client.patch(f"/api/v1/tasks/{task['id']}", headers=owner_headers, json=body)
    assert pending.status_code == 202, pending.text
    approval = pending.json()["approval_request"]
    assert approval["request_type"] == "HANDLER_TRANSFER"
    assert approval["requester_id"] == owner["user"]["id"]
    assert approval["approver_id"] == partner["user"]["id"]
    assert pending.json()["pending"] is True

    before_approval = client.get(f"/api/v1/tasks/{task['id']}", headers=owner_headers)
    assert before_approval.status_code == 200, before_approval.text
    assert before_approval.json()["current_handler_id"] == owner["user"]["id"]

    replay = client.patch(f"/api/v1/tasks/{task['id']}", headers=owner_headers, json=body)
    assert replay.status_code == 202, replay.text
    assert replay.json()["approval_request"]["id"] == approval["id"]
    assert replay.json()["approval_request"]["request_id"] == request_id

    approved = client.post(
        f"/api/v1/workspaces/{task['workspace_id']}/approval-requests/{approval['id']}/approve",
        headers=partner_headers,
        json={"request_id": str(uuid4())},
    )
    assert approved.status_code == 200, approved.text
    assert approved.json()["approval_request"]["status"] == "APPROVED"
    assert approved.json()["task"]["current_handler_id"] == partner["user"]["id"]


def test_owner_handler_patch_can_be_rejected_without_mutating_task(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    owner_headers = _headers(owner)
    partner_headers = _headers(partner)
    task = client.post(
        "/api/v1/tasks",
        headers=owner_headers,
        json={"request_id": str(uuid4()), "title": "Rejected transfer", "quadrant": "Q1", "labels": ["工作"]},
    ).json()
    pending = client.patch(
        f"/api/v1/tasks/{task['id']}",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"current_handler_id": partner["user"]["id"]},
            "base_field_versions": {"current_handler_id": task["field_versions"]["current_handler_id"]},
        },
    )
    assert pending.status_code == 202, pending.text
    approval = pending.json()["approval_request"]

    rejected = client.post(
        f"/api/v1/workspaces/{task['workspace_id']}/approval-requests/{approval['id']}/reject",
        headers=partner_headers,
        json={"request_id": str(uuid4()), "reason": "暂不转交"},
    )
    assert rejected.status_code == 200, rejected.text
    assert rejected.json()["approval_request"]["status"] == "REJECTED"
    assert rejected.json()["task"]["current_handler_id"] == owner["user"]["id"]


def test_lifecycle_complete_submits_review_and_rejection_returns_task_snapshot(db_engine) -> None:
    client = _client(db_engine)
    owner, reviewer = _ready_workspace(client)
    owner_headers = _headers(owner)
    reviewer_headers = _headers(reviewer)
    created = client.post(
        "/api/v1/tasks",
        headers=owner_headers,
        json={"request_id": str(uuid4()), "title": "Lifecycle review", "quadrant": "Q1", "labels": ["工作"]},
    )
    assert created.status_code == 201, created.text
    task = created.json()
    started = client.post(
        f"/api/v1/tasks/{task['id']}/transition",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "target_status": "IN_PROGRESS",
            "base_status_version": task["status_version"],
        },
    )
    assert started.status_code == 200, started.text

    submitted = client.post(
        f"/api/v1/tasks/{task['id']}/lifecycle",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "action": "complete",
            "base_lifecycle_version": started.json()["lifecycle_version"],
            "review_content": "已完成生命周期交付并核对结果",
        },
    )
    assert submitted.status_code == 202, submitted.text
    approval = submitted.json()["approval_request"]
    assert submitted.json()["task"]["status"] == "REVIEW"
    assert approval["approver_id"] == reviewer["user"]["id"]

    missing_reason = client.post(
        f"/api/v1/workspaces/{task['workspace_id']}/approval-requests/{approval['id']}/reject",
        headers=reviewer_headers,
        json={"request_id": str(uuid4())},
    )
    assert missing_reason.status_code == 422, missing_reason.text
    assert missing_reason.json()["code"] == "invalid_request"

    rejected = client.post(
        f"/api/v1/workspaces/{task['workspace_id']}/approval-requests/{approval['id']}/reject",
        headers=reviewer_headers,
        json={"request_id": str(uuid4()), "reason": "补充验收材料"},
    )
    assert rejected.status_code == 200, rejected.text
    assert rejected.json()["approval_request"]["status"] == "REJECTED"
    assert rejected.json()["task"]["status"] == "IN_PROGRESS"
    assert rejected.json()["task"]["review_rejection_reason"] == "补充验收材料"


def test_review_submission_preserves_content_and_viewer_next_step(db_engine) -> None:
    client = _client(db_engine)
    owner, reviewer = _ready_workspace(client)
    owner_headers = _headers(owner)
    reviewer_headers = _headers(reviewer)
    created = client.post(
        "/api/v1/tasks",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "title": "验收内容",
            "quadrant": "Q1",
            "labels": ["工作"],
        },
    )
    assert created.status_code == 201, created.text
    task = created.json()
    started = client.post(
        f"/api/v1/tasks/{task['id']}/transition",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "target_status": "IN_PROGRESS",
            "base_status_version": task["status_version"],
        },
    )
    assert started.status_code == 200, started.text
    content = "  已确认最终版本，附件与现场结果一致。  "
    submit_body = {
        "request_id": str(uuid4()),
        "target_status": "REVIEW",
        "base_status_version": started.json()["status_version"],
        "review_content": content,
    }
    submitted = client.post(
        f"/api/v1/tasks/{task['id']}/transition",
        headers=owner_headers,
        json=submit_body,
    )
    assert submitted.status_code == 202, submitted.text
    payload = submitted.json()
    approval = payload["approval_request"]
    assert approval["proposed_changes"]["review_content"] == content.strip()
    replay = client.post(
        f"/api/v1/tasks/{task['id']}/transition",
        headers=owner_headers,
        json=submit_body,
    )
    assert replay.status_code == 202, replay.text
    assert replay.json()["approval_request"]["id"] == approval["id"]

    owner_view = client.get(f"/api/v1/tasks/{task['id']}", headers=owner_headers)
    assert owner_view.status_code == 200, owner_view.text
    assert owner_view.json()["next_step"] == {
        "kind": "WAITING_FOR_REVIEW",
        "label": "等待对方验收",
        "request_id": approval["id"],
        "can_act": False,
        "actions": [],
    }
    reviewer_view = client.get(f"/api/v1/tasks/{task['id']}", headers=reviewer_headers)
    assert reviewer_view.status_code == 200, reviewer_view.text
    assert reviewer_view.json()["next_step"] == {
        "kind": "ACCEPT_OR_RETURN_REVIEW",
        "label": "确认验收结果",
        "request_id": approval["id"],
        "can_act": True,
        "actions": ["APPROVE_REVIEW", "RETURN_REVIEW"],
    }

    timeline = client.get(f"/api/v1/tasks/{task['id']}/activity", headers=owner_headers)
    assert timeline.status_code == 200, timeline.text
    review_events = [
        item
        for item in timeline.json()
        if item.get("kind") == "activity"
        and item.get("event_type") == "APPROVAL_REQUESTED"
        and item.get("payload", {}).get("approval_request", {}).get("id") == approval["id"]
    ]
    assert review_events
    assert review_events[0]["payload"]["approval_request"]["proposed_changes"]["review_content"] == content.strip()


def test_review_next_step_ignores_newer_unrelated_pending_task_update(db_engine) -> None:
    client = _client(db_engine)
    owner, reviewer = _ready_workspace(client)
    owner_headers = _headers(owner)
    reviewer_headers = _headers(reviewer)
    created = client.post(
        "/api/v1/tasks",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "title": "验收请求优先级",
            "quadrant": "Q1",
            "labels": ["工作"],
        },
    )
    assert created.status_code == 201, created.text
    task = created.json()
    started = client.post(
        f"/api/v1/tasks/{task['id']}/transition",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "target_status": "IN_PROGRESS",
            "base_status_version": task["status_version"],
        },
    )
    assert started.status_code == 200, started.text
    submitted = client.post(
        f"/api/v1/tasks/{task['id']}/transition",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "target_status": "REVIEW",
            "base_status_version": started.json()["status_version"],
            "review_content": "已完成验收材料整理",
        },
    )
    assert submitted.status_code == 202, submitted.text
    review_request = submitted.json()["approval_request"]

    unrelated = client.patch(
        f"/api/v1/tasks/{task['id']}",
        headers=reviewer_headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"title": "对方提出的标题建议"},
            "base_field_versions": {
                "title": task["field_versions"]["title"],
            },
        },
    )
    assert unrelated.status_code == 202, unrelated.text
    assert unrelated.json()["approval_request"]["request_type"] == "TASK_UPDATE"

    reviewer_view = client.get(f"/api/v1/tasks/{task['id']}", headers=reviewer_headers)
    assert reviewer_view.status_code == 200, reviewer_view.text
    assert reviewer_view.json()["next_step"] == {
        "kind": "ACCEPT_OR_RETURN_REVIEW",
        "label": "确认验收结果",
        "request_id": review_request["id"],
        "can_act": True,
        "actions": ["APPROVE_REVIEW", "RETURN_REVIEW"],
    }


def test_review_submission_requires_content_over_http(db_engine) -> None:
    client = _client(db_engine)
    owner, _reviewer = _ready_workspace(client)
    owner_headers = _headers(owner)
    created = client.post(
        "/api/v1/tasks",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "title": "验收内容必填",
            "quadrant": "Q1",
            "labels": ["工作"],
        },
    )
    assert created.status_code == 201, created.text
    task = created.json()
    started = client.post(
        f"/api/v1/tasks/{task['id']}/transition",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "target_status": "IN_PROGRESS",
            "base_status_version": task["status_version"],
        },
    )
    assert started.status_code == 200, started.text

    submitted = client.post(
        f"/api/v1/tasks/{task['id']}/transition",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "target_status": "REVIEW",
            "base_status_version": started.json()["status_version"],
        },
    )
    assert submitted.status_code == 422, submitted.text
    assert submitted.json()["code"] == "invalid_request"

    current = client.get(f"/api/v1/tasks/{task['id']}", headers=owner_headers)
    assert current.status_code == 200, current.text
    assert current.json()["status"] == "IN_PROGRESS"

    blank = client.post(
        f"/api/v1/tasks/{task['id']}/transition",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "target_status": "REVIEW",
            "base_status_version": started.json()["status_version"],
            "review_content": "   ",
        },
    )
    assert blank.status_code == 422, blank.text
    assert blank.json()["code"] == "invalid_request"


def test_handler_transfer_preserves_transfer_note_in_approval_and_activity(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    owner_headers = _headers(owner)
    partner_headers = _headers(partner)
    created = client.post(
        "/api/v1/tasks",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "title": "交接说明",
            "quadrant": "Q2",
            "labels": ["工作"],
        },
    )
    assert created.status_code == 201, created.text
    task = created.json()
    note = "后续继续跟进供应商合同并确认最终交付时间。"
    pending = client.patch(
        f"/api/v1/tasks/{task['id']}",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "changes": {
                "current_handler_id": partner["user"]["id"],
                "transfer_note": note,
            },
            "base_field_versions": {
                "current_handler_id": task["field_versions"]["current_handler_id"]
            },
        },
    )
    assert pending.status_code == 202, pending.text
    approval = pending.json()["approval_request"]
    assert approval["request_type"] == "HANDLER_TRANSFER"
    assert approval["proposed_changes"]["transfer_note"] == note

    timeline = client.get(f"/api/v1/tasks/{task['id']}/activity", headers=partner_headers)
    assert timeline.status_code == 200, timeline.text
    transfer_events = [
        item
        for item in timeline.json()
        if item.get("kind") == "activity"
        and item.get("event_type") == "APPROVAL_REQUESTED"
        and item.get("payload", {}).get("approval_request", {}).get("id") == approval["id"]
    ]
    assert transfer_events
    assert transfer_events[0]["payload"]["approval_request"]["proposed_changes"]["transfer_note"] == note


def test_handler_transfer_trims_note_replays_and_applies_without_duplicate_activity(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    owner_headers = _headers(owner)
    partner_headers = _headers(partner)
    created = client.post(
        "/api/v1/tasks",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "title": "交接应用",
            "quadrant": "Q2",
            "labels": ["工作"],
        },
    )
    assert created.status_code == 201, created.text
    task = created.json()
    request_id = str(uuid4())
    note = "  请继续确认合同最终交付时间。  "
    body = {
        "request_id": request_id,
        "changes": {
            "current_handler_id": partner["user"]["id"],
            "transfer_note": note,
        },
        "base_field_versions": {
            "current_handler_id": task["field_versions"]["current_handler_id"]
        },
    }
    pending = client.patch(f"/api/v1/tasks/{task['id']}", headers=owner_headers, json=body)
    assert pending.status_code == 202, pending.text
    approval = pending.json()["approval_request"]
    assert approval["proposed_changes"]["transfer_note"] == note.strip()

    replay = client.patch(f"/api/v1/tasks/{task['id']}", headers=owner_headers, json=body)
    assert replay.status_code == 202, replay.text
    assert replay.json()["approval_request"]["id"] == approval["id"]

    approved = client.post(
        f"/api/v1/workspaces/{task['workspace_id']}/approval-requests/{approval['id']}/approve",
        headers=partner_headers,
        json={"request_id": str(uuid4())},
    )
    assert approved.status_code == 200, approved.text
    assert approved.json()["task"]["current_handler_id"] == partner["user"]["id"]

    timeline = client.get(f"/api/v1/tasks/{task['id']}/activity", headers=owner_headers)
    assert timeline.status_code == 200, timeline.text
    events = timeline.json()
    approval_events = [
        item
        for item in events
        if item.get("kind") == "activity"
        and item.get("event_type") == "APPROVAL_APPROVED"
        and item.get("payload", {}).get("approval_request", {}).get("id") == approval["id"]
    ]
    assert len(approval_events) == 1
    assert approval_events[0]["payload"]["approval_request"]["proposed_changes"]["transfer_note"] == note.strip()
    assert len({item["id"] for item in events}) == len(events)


def test_handler_transfer_applies_proposed_next_step_only_after_acceptance(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    owner_headers = _headers(owner)
    partner_headers = _headers(partner)
    created = client.post(
        "/api/v1/tasks",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "title": "交接下一步",
            "next_step_text": "我先整理资料",
            "quadrant": "Q2",
            "labels": ["工作"],
        },
    )
    assert created.status_code == 201, created.text
    task = created.json()
    pending = client.patch(
        f"/api/v1/tasks/{task['id']}",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "changes": {
                "current_handler_id": partner["user"]["id"],
                "transfer_note": "请接手供应商沟通",
                "proposed_next_step": "联系供应商确认交付日期",
            },
            "base_field_versions": {
                "current_handler_id": task["field_versions"]["current_handler_id"],
                "next_step_text": task["field_versions"]["next_step_text"],
            },
        },
    )
    assert pending.status_code == 202, pending.text
    approval = pending.json()["approval_request"]
    assert approval["proposed_changes"]["proposed_next_step"] == "联系供应商确认交付日期"

    before = client.get(f"/api/v1/tasks/{task['id']}", headers=partner_headers)
    assert before.status_code == 200
    assert before.json()["current_handler_id"] == owner["user"]["id"]
    assert before.json()["next_step_text"] == "我先整理资料"

    accepted = client.post(
        f"/api/v1/workspaces/{task['workspace_id']}/approval-requests/{approval['id']}/approve",
        headers=partner_headers,
        json={"request_id": str(uuid4())},
    )
    assert accepted.status_code == 200, accepted.text
    assert accepted.json()["task"]["current_handler_id"] == partner["user"]["id"]
    assert accepted.json()["task"]["next_step_text"] == "联系供应商确认交付日期"


def test_rejected_handler_transfer_keeps_current_next_step(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    owner_headers = _headers(owner)
    partner_headers = _headers(partner)
    created = client.post(
        "/api/v1/tasks",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "title": "拒绝交接下一步",
            "next_step_text": "保留原下一步",
            "quadrant": "Q2",
            "labels": ["工作"],
        },
    ).json()
    pending = client.patch(
        f"/api/v1/tasks/{created['id']}",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "changes": {
                "current_handler_id": partner["user"]["id"],
                "proposed_next_step": "不应写入",
            },
            "base_field_versions": {
                "current_handler_id": created["field_versions"]["current_handler_id"],
                "next_step_text": created["field_versions"]["next_step_text"],
            },
        },
    ).json()
    rejected = client.post(
        f"/api/v1/workspaces/{created['workspace_id']}/approval-requests/{pending['approval_request']['id']}/reject",
        headers=partner_headers,
        json={"request_id": str(uuid4()), "reason": "暂不接手"},
    )
    assert rejected.status_code == 200, rejected.text
    assert rejected.json()["task"]["current_handler_id"] == owner["user"]["id"]
    assert rejected.json()["task"]["next_step_text"] == "保留原下一步"


def test_review_rejection_projects_resubmission_for_owner_only(db_engine) -> None:
    client = _client(db_engine)
    owner, reviewer = _ready_workspace(client)
    owner_headers = _headers(owner)
    reviewer_headers = _headers(reviewer)
    created = client.post(
        "/api/v1/tasks",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "title": "退回验收",
            "quadrant": "Q1",
            "labels": ["工作"],
        },
    )
    assert created.status_code == 201, created.text
    task = created.json()
    started = client.post(
        f"/api/v1/tasks/{task['id']}/transition",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "target_status": "IN_PROGRESS",
            "base_status_version": task["status_version"],
        },
    )
    assert started.status_code == 200, started.text
    submitted = client.post(
        f"/api/v1/tasks/{task['id']}/transition",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "target_status": "REVIEW",
            "base_status_version": started.json()["status_version"],
            "review_content": "已完成首轮核对",
        },
    )
    assert submitted.status_code == 202, submitted.text
    approval = submitted.json()["approval_request"]
    rejected = client.post(
        f"/api/v1/workspaces/{task['workspace_id']}/approval-requests/{approval['id']}/reject",
        headers=reviewer_headers,
        json={"request_id": str(uuid4()), "reason": "请补充最终交付时间"},
    )
    assert rejected.status_code == 200, rejected.text
    assert rejected.json()["task"]["status"] == "IN_PROGRESS"

    owner_view = client.get(f"/api/v1/tasks/{task['id']}", headers=owner_headers)
    assert owner_view.status_code == 200, owner_view.text
    assert owner_view.json()["next_step"] == {
        "kind": "RESUBMIT_REVIEW",
        "label": "修改后重新提交验收",
        "can_act": True,
        "actions": ["SUBMIT_REVIEW"],
    }
    reviewer_view = client.get(f"/api/v1/tasks/{task['id']}", headers=reviewer_headers)
    assert reviewer_view.status_code == 200, reviewer_view.text
    assert reviewer_view.json()["next_step"] == {
        "kind": "NO_ACTION",
        "label": "等待负责人修改",
        "can_act": False,
        "actions": [],
    }


def test_activity_returns_one_payload_event_per_operation(db_engine) -> None:
    client = _client(db_engine)
    owner, _partner = _ready_workspace(client)
    owner_headers = _headers(owner)
    created = client.post(
        "/api/v1/tasks",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "title": "活动去重",
            "quadrant": "Q3",
            "labels": ["工作"],
        },
    )
    assert created.status_code == 201, created.text
    task = created.json()

    timeline = client.get(f"/api/v1/tasks/{task['id']}/activity", headers=owner_headers)
    assert timeline.status_code == 200, timeline.text
    events = timeline.json()
    assert len(events) == 1
    assert events[0]["kind"] == "activity"
    assert events[0]["payload"]["after"]["id"] == task["id"]


def test_handler_transfer_is_rejected_while_task_is_in_review(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    owner_headers = _headers(owner)
    partner_headers = _headers(partner)
    created = client.post(
        "/api/v1/tasks",
        headers=owner_headers,
        json={"request_id": str(uuid4()), "title": "Review conflict", "quadrant": "Q1", "labels": ["工作"]},
    )
    assert created.status_code == 201, created.text
    task = created.json()

    started = client.post(
        f"/api/v1/tasks/{task['id']}/transition",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "target_status": "IN_PROGRESS",
            "base_status_version": task["status_version"],
        },
    )
    assert started.status_code == 200, started.text
    submitted = client.post(
        f"/api/v1/tasks/{task['id']}/transition",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "target_status": "REVIEW",
            "base_status_version": started.json()["status_version"],
            "review_content": "已完成任务核对",
        },
    )
    assert submitted.status_code == 202, submitted.text
    transfer = client.patch(
        f"/api/v1/tasks/{task['id']}",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"current_handler_id": partner["user"]["id"]},
            "base_field_versions": {"current_handler_id": task["field_versions"]["current_handler_id"]},
        },
    )
    assert transfer.status_code == 403, transfer.text
    assert transfer.json()["code"] == "approval_not_allowed"
    assert transfer.json()["message"] == "handler transfer is not allowed while task is in review"
    current = client.get(f"/api/v1/tasks/{task['id']}", headers=partner_headers)
    assert current.status_code == 200, current.text
    assert current.json()["status"] == "REVIEW"
    assert current.json()["current_handler_id"] == owner["user"]["id"]
    assert current.json()["reviewer_user_id"] == partner["user"]["id"]


def test_review_rejection_requires_acceptance_request_and_reason(db_engine) -> None:
    client = _client(db_engine)
    owner, reviewer = _ready_workspace(client)
    owner_headers = _headers(owner)
    reviewer_headers = _headers(reviewer)
    created = client.post(
        "/api/v1/tasks",
        headers=owner_headers,
        json={"request_id": str(uuid4()), "title": "Review 409", "quadrant": "Q1", "labels": ["工作"]},
    ).json()
    started = client.post(
        f"/api/v1/tasks/{created['id']}/transition",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "target_status": "IN_PROGRESS",
            "base_status_version": created["status_version"],
        },
    ).json()
    submitted_response = client.post(
        f"/api/v1/tasks/{created['id']}/transition",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "target_status": "REVIEW",
            "base_status_version": started["status_version"],
            "review_content": "已完成任务核对",
        },
    )
    assert submitted_response.status_code == 202, submitted_response.text
    payload = submitted_response.json()
    approval = payload["approval_request"]
    submitted = payload["task"]

    missing_reason = client.post(
        f"/api/v1/tasks/{created['id']}/transition",
        headers=reviewer_headers,
        json={
            "request_id": str(uuid4()),
            "target_status": "IN_PROGRESS",
            "base_status_version": submitted["status_version"],
        },
    )
    assert missing_reason.status_code == 422, missing_reason.text
    assert missing_reason.json()["code"] == "invalid_request"

    rejected = client.post(
        f"/api/v1/workspaces/{created['workspace_id']}/approval-requests/{approval['id']}/reject",
        headers=reviewer_headers,
        json={"request_id": str(uuid4()), "reason": "补充验收材料"},
    )
    assert rejected.status_code == 200, rejected.text
    assert rejected.json()["approval_request"]["status"] == "REJECTED"
    assert rejected.json()["task"]["status"] == "IN_PROGRESS"
    assert rejected.json()["task"]["review_rejection_reason"] == "补充验收材料"


def test_stale_patch_request_replays_the_original_409_across_http_sessions(db_engine) -> None:
    client = _client(db_engine)
    replay_client = _client(db_engine)
    owner, _partner = _ready_workspace(client)
    headers = _headers(owner)
    created = client.post(
        "/api/v1/tasks",
        headers=headers,
        json={"request_id": str(uuid4()), "title": "HTTP replay", "quadrant": "Q1", "labels": ["工作"]},
    )
    assert created.status_code == 201, created.text
    task = created.json()
    changed = client.patch(
        f"/api/v1/tasks/{task['id']}",
        headers=headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"title": "Current title"},
            "base_field_versions": {"title": task["field_versions"]["title"]},
        },
    )
    assert changed.status_code == 200, changed.text

    request_id = str(uuid4())
    body = {
        "request_id": request_id,
        "changes": {"title": "Proposed title"},
        "base_field_versions": {"title": task["field_versions"]["title"]},
    }
    first = client.patch(f"/api/v1/tasks/{task['id']}", headers=headers, json=body)

    assert first.status_code == 409, first.text
    conflict_id = first.json()["details"]["conflicts"][0]["id"]
    resolved = replay_client.post(
        f"/api/v1/tasks/{task['id']}/conflicts/{conflict_id}/resolve",
        headers=headers,
        json={"request_id": str(uuid4()), "resolution": "current"},
    )
    assert resolved.status_code == 200, resolved.text
    before_replay = _side_effect_counts(db_engine, task["workspace_id"], task["id"])
    replay = replay_client.patch(f"/api/v1/tasks/{task['id']}", headers=headers, json=body)
    assert replay.status_code == 409, replay.text
    assert replay.json() == first.json()
    assert _side_effect_counts(db_engine, task["workspace_id"], task["id"]) == before_replay
    assert first.json()["details"]["conflicts"][0]["current_snapshot"]["title"] == "Current title"
    assert isinstance(first.json()["details"]["cursor"], int)


def test_stale_status_request_replays_the_original_409_across_http_sessions(db_engine) -> None:
    client = _client(db_engine)
    replay_client = _client(db_engine)
    owner, _partner = _ready_workspace(client)
    headers = _headers(owner)
    created = client.post(
        "/api/v1/tasks",
        headers=headers,
        json={"request_id": str(uuid4()), "title": "HTTP status replay", "quadrant": "Q1", "labels": ["工作"]},
    ).json()
    started = client.post(
        f"/api/v1/tasks/{created['id']}/transition",
        headers=headers,
        json={
            "request_id": str(uuid4()),
            "target_status": "IN_PROGRESS",
            "base_status_version": created["status_version"],
        },
    )
    assert started.status_code == 200, started.text

    request_id = str(uuid4())
    body = {
        "request_id": request_id,
        "target_status": "BLOCKED",
        "base_status_version": created["status_version"],
        "blocked_reason": "等待资料",
        "resume_handler_id": owner["user"]["id"],
    }
    first = client.post(f"/api/v1/tasks/{created['id']}/transition", headers=headers, json=body)

    assert first.status_code == 409, first.text
    conflict_id = first.json()["details"]["conflicts"][0]["id"]
    resolved = replay_client.post(
        f"/api/v1/tasks/{created['id']}/conflicts/{conflict_id}/resolve",
        headers=headers,
        json={"request_id": str(uuid4()), "resolution": "proposed"},
    )
    assert resolved.status_code == 200, resolved.text
    assert resolved.json()["status"] == "BLOCKED"
    before_replay = _side_effect_counts(db_engine, created["workspace_id"], created["id"])
    replay = replay_client.post(f"/api/v1/tasks/{created['id']}/transition", headers=headers, json=body)
    assert replay.status_code == 409, replay.text
    assert replay.json() == first.json()
    assert _side_effect_counts(db_engine, created["workspace_id"], created["id"]) == before_replay
    assert first.json()["details"]["conflicts"][0]["proposed_payload"]["target_status"] == "BLOCKED"
    assert isinstance(first.json()["details"]["cursor"], int)


def test_owner_handler_transfer_approval_cancels_when_owner_is_stale(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    owner_headers = _headers(owner)
    partner_headers = _headers(partner)
    created = client.post(
        "/api/v1/tasks",
        headers=owner_headers,
        json={"request_id": str(uuid4()), "title": "Handler replay", "quadrant": "Q1", "labels": ["工作"]},
    ).json()
    pending = client.patch(
        f"/api/v1/tasks/{created['id']}",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"current_handler_id": partner["user"]["id"]},
            "base_field_versions": {"current_handler_id": 1},
        },
    )
    assert pending.status_code == 202, pending.text
    approval = pending.json()["approval_request"]

    with Session(db_engine) as session:
        task_row = session.get(Task, created["id"])
        assert task_row is not None
        TaskService(session).patch(
            task_row.workspace_id,
            task_row.current_handler_id,
            task_row.id,
            uuid4(),
            {"current_handler_id": partner["user"]["id"]},
            {"current_handler_id": task_row.field_versions["current_handler_id"]},
        )
        session.commit()

    stale = client.post(
        f"/api/v1/workspaces/{created['workspace_id']}/approval-requests/{approval['id']}/approve",
        headers=partner_headers,
        json={"request_id": str(uuid4())},
    )
    assert stale.status_code == 409, stale.text
    assert stale.json()["code"] == "approval_conflicted"
    current = client.get(f"/api/v1/tasks/{created['id']}", headers=partner_headers)
    assert current.status_code == 200, current.text
    assert current.json()["current_handler_id"] == partner["user"]["id"]


def test_stale_blocked_status_409_uses_full_conflict_projection(db_engine) -> None:
    client = _client(db_engine)
    owner, _reviewer = _ready_workspace(client)
    owner_headers = _headers(owner)
    created = client.post(
        "/api/v1/tasks",
        headers=owner_headers,
        json={"request_id": str(uuid4()), "title": "Blocked 409", "quadrant": "Q2", "labels": ["工作"]},
    ).json()
    started = client.post(
        f"/api/v1/tasks/{created['id']}/transition",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "target_status": "IN_PROGRESS",
            "base_status_version": created["status_version"],
        },
    ).json()
    blocked = client.post(
        f"/api/v1/tasks/{created['id']}/transition",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "target_status": "BLOCKED",
            "base_status_version": started["status_version"],
            "blocked_reason": "等待外部材料",
            "resume_handler_id": owner["user"]["id"],
        },
    ).json()

    stale = client.post(
        f"/api/v1/tasks/{created['id']}/transition",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "target_status": "IN_PROGRESS",
            "base_status_version": started["status_version"],
        },
    )
    assert stale.status_code == 409, stale.text
    http_conflict = stale.json()["details"]["conflicts"][0]

    listed = client.get(f"/api/v1/tasks/{created['id']}/conflicts", headers=owner_headers)
    assert listed.status_code == 200, listed.text
    get_conflict = listed.json()[0]
    assert http_conflict == get_conflict
    assert http_conflict["current_snapshot"] == {
        **http_conflict["current_snapshot"],
        "status": "BLOCKED",
        "blocked_reason": "等待外部材料",
        "blocked_since": blocked["blocked_since"],
        "resume_handler_id": owner["user"]["id"],
        "status_version": blocked["status_version"],
        "lifecycle_version": blocked["lifecycle_version"],
    }
    assert http_conflict["status_version"] == blocked["status_version"]
    assert http_conflict["lifecycle_version"] == blocked["lifecycle_version"]
    assert http_conflict["field_versions"] == blocked["field_versions"]


def test_owner_comment_delete_is_pending_and_comment_author_approves(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    owner_headers = _headers(owner)
    partner_headers = _headers(partner)
    created = client.post(
        "/api/v1/tasks",
        headers=owner_headers,
        json={"request_id": str(uuid4()), "title": "Comment task", "quadrant": "Q1", "labels": ["工作"]},
    ).json()
    comment = client.post(
        f"/api/v1/tasks/{created['id']}/comments",
        headers=partner_headers,
        json={"request_id": str(uuid4()), "body": "Audit me"},
    )
    assert comment.status_code == 201, comment.text
    assert comment.json()["workspace_id"] == created["workspace_id"]

    pending = client.request(
        "DELETE",
        f"/api/v1/tasks/{created['id']}/comments/{comment.json()['id']}",
        headers=owner_headers,
        json={"request_id": str(uuid4()), "base_version": 1},
    )
    assert pending.status_code == 202, pending.text
    approval = pending.json()["approval_request"]
    assert approval["request_type"] == "COMMENT_DELETE"
    assert approval["approver_id"] == partner["user"]["id"]

    approved = client.post(
        f"/api/v1/workspaces/{created['workspace_id']}/approval-requests/{approval['id']}/approve",
        headers=partner_headers,
        json={"request_id": str(uuid4())},
    )
    assert approved.status_code == 200, approved.text
    assert approved.json()["comment"]["deleted_at"] is not None


def test_approval_workspace_path_must_match_authenticated_workspace(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    task = client.post(
        "/api/v1/tasks",
        headers=_headers(owner),
        json={"request_id": str(uuid4()), "title": "Scoped", "quadrant": "Q1", "labels": ["工作"]},
    ).json()
    foreign_workspace = uuid4()
    response = client.post(
        f"/api/v1/workspaces/{foreign_workspace}/approval-requests",
        headers=_headers(partner),
        json={
            "request_id": str(uuid4()),
            "task_id": task["id"],
            "request_type": "TASK_UPDATE",
            "proposed_changes": {"title": "Nope"},
            "base_field_versions": {"title": 1},
        },
    )
    assert response.status_code == 403, response.text
    assert response.json()["code"] == "workspace_access_denied"
