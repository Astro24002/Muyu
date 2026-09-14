from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import uuid4

from fastapi.testclient import TestClient

from app.main import create_app

from tests.httpapi.test_device_readonly_permissions import _headers, _ready_workspace
from tests.httpapi.test_lightweight_routes import FakeSmsProvider


def _client(db_engine) -> TestClient:
    app = create_app()
    app.state.engine = db_engine
    app.state.ready = True
    app.state.sms_provider = FakeSmsProvider()
    return TestClient(app)


def _assert_home(
    client: TestClient,
    headers: dict[str, str],
    *,
    task_id: str,
    mine: bool,
    in_moment: bool = True,
    needs_action: int,
    waiting_on_other: int,
    week_due: int,
) -> dict[str, object]:
    response = client.get("/api/v1/home", headers=headers)
    assert response.status_code == 200, response.text
    body = response.json()
    moment = body["moment"]
    assert isinstance(moment, dict)
    for section_name in ("blocked_tasks", "my_tasks", "other_tasks"):
        section = moment[section_name]
        assert isinstance(section, dict)
        assert section["has_more"] is False

    blocked_ids = {item["id"] for item in moment["blocked_tasks"]["items"]}
    mine_ids = {item["id"] for item in moment["my_tasks"]["items"]}
    other_ids = {item["id"] for item in moment["other_tasks"]["items"]}
    assert not blocked_ids
    if in_moment:
        assert (mine_ids if mine else other_ids) == {task_id}
        assert (other_ids if mine else mine_ids) == set()
    else:
        assert not mine_ids
        assert not other_ids
    assert body["needs_action_count"] == needs_action
    assert body["waiting_on_other_count"] == waiting_on_other
    assert body["week_due_count"] == week_due
    return body


def _assert_sync_continuity(
    client: TestClient,
    owner_headers: dict[str, str],
    partner_headers: dict[str, str],
    *,
    after_cursor: int,
    task_id: str,
    expected_status: str,
    expected_handler_id: str,
) -> int:
    owner_snapshot_response = client.get(
        "/api/v1/workspaces/current/snapshot", headers=owner_headers
    )
    partner_snapshot_response = client.get(
        "/api/v1/workspaces/current/snapshot", headers=partner_headers
    )
    assert owner_snapshot_response.status_code == 200, owner_snapshot_response.text
    assert partner_snapshot_response.status_code == 200, partner_snapshot_response.text
    owner_snapshot = owner_snapshot_response.json()
    partner_snapshot = partner_snapshot_response.json()
    assert owner_snapshot["viewer_user_id"] != partner_snapshot["viewer_user_id"]
    assert owner_snapshot["cursor"] == partner_snapshot["cursor"]
    cursor = owner_snapshot["cursor"]
    assert cursor > after_cursor
    owner_task = next(item for item in owner_snapshot["tasks"] if item["id"] == task_id)
    partner_task = next(item for item in partner_snapshot["tasks"] if item["id"] == task_id)
    assert owner_task == partner_task
    assert owner_task["status"] == expected_status
    assert owner_task["current_handler_id"] == expected_handler_id

    changes_response = client.get(
        f"/api/v1/workspaces/current/changes?after_cursor={after_cursor}",
        headers=partner_headers,
    )
    assert changes_response.status_code == 200, changes_response.text
    changes = changes_response.json()
    change_cursors = [item["cursor"] for item in changes["changes"]]
    assert change_cursors == list(range(after_cursor + 1, cursor + 1))
    assert changes["cursor"] == cursor
    return cursor


def test_two_users_complete_task_approval_and_sync_lifecycle(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    owner_headers = _headers(owner)
    partner_headers = _headers(partner)

    created_response = client.post(
        "/api/v1/tasks",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "title": "Shared task",
            "quadrant": "Q2",
            "labels": ["工作"],
        },
    )
    assert created_response.status_code == 201, created_response.text
    task = created_response.json()
    task_id = task["id"]
    workspace_id = task["workspace_id"]
    assert task["task_number"].isdigit()
    assert task["quadrant"] == "Q2"
    assert task["labels"] == ["工作"]
    assert task["current_handler_id"] == owner["user"]["id"]
    assert "assignee_ids" not in task

    pending_response = client.patch(
        f"/api/v1/tasks/{task_id}",
        headers=partner_headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"title": "Partner proposal"},
            "base_field_versions": {"title": task["field_versions"]["title"]},
        },
    )
    assert pending_response.status_code == 202, pending_response.text
    approval = pending_response.json()["approval_request"]
    assert approval["requester_id"] == partner["user"]["id"]
    assert approval["approver_id"] == owner["user"]["id"]

    incoming = client.get(
        f"/api/v1/workspaces/{workspace_id}/approval-requests?box=incoming",
        headers=owner_headers,
    )
    assert incoming.status_code == 200, incoming.text
    assert incoming.json()[0]["id"] == approval["id"]

    approved = client.post(
        f"/api/v1/workspaces/{workspace_id}/approval-requests/{approval['id']}/approve",
        headers=owner_headers,
        json={"request_id": str(uuid4())},
    )
    assert approved.status_code == 200, approved.text
    assert approved.json()["approval_request"]["status"] == "APPROVED"
    assert approved.json()["task"]["title"] == "Partner proposal"
    assert "assignee_ids" not in approved.json()["task"]

    partner_snapshot = client.get(
        "/api/v1/workspaces/current/snapshot", headers=partner_headers
    )
    assert partner_snapshot.status_code == 200, partner_snapshot.text
    assert partner_snapshot.json()["viewer_user_id"] == partner["user"]["id"]
    assert partner_snapshot.json()["tasks"][0]["title"] == "Partner proposal"
    assert partner_snapshot.json()["tasks"][0]["quadrant"] == "Q2"
    assert partner_snapshot.json()["tasks"][0]["labels"] == ["工作"]
    assert "assignee_ids" not in partner_snapshot.json()["tasks"][0]

    comment = client.post(
        f"/api/v1/tasks/{task_id}/comments",
        headers=partner_headers,
        json={"request_id": str(uuid4()), "body": "Keep the audit trail"},
    )
    assert comment.status_code == 201, comment.text
    comment_id = comment.json()["id"]
    delete_pending = client.request(
        "DELETE",
        f"/api/v1/tasks/{task_id}/comments/{comment_id}",
        headers=owner_headers,
        json={"request_id": str(uuid4()), "base_version": 1},
    )
    assert delete_pending.status_code == 202, delete_pending.text
    comment_approval = delete_pending.json()["approval_request"]
    assert comment_approval["request_type"] == "COMMENT_DELETE"
    assert comment_approval["approver_id"] == partner["user"]["id"]

    comment_approved = client.post(
        f"/api/v1/workspaces/{workspace_id}/approval-requests/{comment_approval['id']}/approve",
        headers=partner_headers,
        json={"request_id": str(uuid4())},
    )
    assert comment_approved.status_code == 200, comment_approved.text
    assert comment_approved.json()["comment"]["deleted_at"] is not None

    stale = client.patch(
        f"/api/v1/tasks/{task_id}",
        headers=partner_headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"title": "Stale proposal"},
            "base_field_versions": {"title": approved.json()["task"]["field_versions"]["title"]},
        },
    )
    assert stale.status_code == 202, stale.text
    stale_approval = stale.json()["approval_request"]
    owner_edit = client.patch(
        f"/api/v1/tasks/{task_id}",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"title": "Owner wins"},
            "base_field_versions": {"title": approved.json()["task"]["field_versions"]["title"]},
        },
    )
    assert owner_edit.status_code == 200, owner_edit.text
    stale_result = client.post(
        f"/api/v1/workspaces/{workspace_id}/approval-requests/{stale_approval['id']}/approve",
        headers=owner_headers,
        json={"request_id": str(uuid4())},
    )
    assert stale_result.status_code == 409, stale_result.text
    assert stale_result.json()["code"] == "approval_conflicted"

    transfer_pending = client.patch(
        f"/api/v1/tasks/{task_id}",
        headers=partner_headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"description": "Transfer after review"},
            "base_field_versions": {"description": owner_edit.json()["field_versions"]["description"]},
        },
    )
    assert transfer_pending.status_code == 202, transfer_pending.text
    transfer_request = transfer_pending.json()["approval_request"]
    transfer = client.patch(
        f"/api/v1/tasks/{task_id}",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "changes": {"current_handler_id": partner["user"]["id"]},
            "base_field_versions": {"current_handler_id": owner_edit.json()["field_versions"]["current_handler_id"]},
        },
    )
    assert transfer.status_code == 202, transfer.text
    owner_transfer = transfer.json()["approval_request"]
    assert owner_transfer["request_type"] == "HANDLER_TRANSFER"
    assert owner_transfer["requester_id"] == owner["user"]["id"]
    assert owner_transfer["approver_id"] == partner["user"]["id"]

    approved_transfer = client.post(
        f"/api/v1/workspaces/{workspace_id}/approval-requests/{owner_transfer['id']}/approve",
        headers=partner_headers,
        json={"request_id": str(uuid4())},
    )
    assert approved_transfer.status_code == 200, approved_transfer.text
    assert approved_transfer.json()["approval_request"]["status"] == "APPROVED"
    assert approved_transfer.json()["task"]["current_handler_id"] == partner["user"]["id"]
    outgoing = client.get(
        f"/api/v1/workspaces/{workspace_id}/approval-requests?box=outgoing",
        headers=partner_headers,
    )
    assert outgoing.status_code == 200, outgoing.text
    assert next(item for item in outgoing.json() if item["id"] == transfer_request["id"])["status"] == "CANCELLED"

    owner_final = client.get("/api/v1/workspaces/current/snapshot", headers=owner_headers)
    partner_final = client.get("/api/v1/workspaces/current/snapshot", headers=partner_headers)
    assert owner_final.status_code == partner_final.status_code == 200
    assert owner_final.json()["cursor"] == partner_final.json()["cursor"]
    assert owner_final.json()["tasks"] == partner_final.json()["tasks"]
    assert owner_final.json()["tasks"][0]["quadrant"] == "Q2"
    assert owner_final.json()["tasks"][0]["labels"] == ["工作"]
    assert "assignee_ids" not in owner_final.json()["tasks"][0]
    assert any(item["id"] == comment_id and item["deleted_at"] for item in owner_final.json()["comments"])
    print(
        "two-person task approval smoke: "
        f"task_number={owner_final.json()['tasks'][0]['task_number']} "
        f"request_id={approval['request_id']} "
        f"approval_status={approved.json()['approval_request']['status']} "
        f"final_cursor={owner_final.json()['cursor']}"
    )


def test_two_users_complete_moment_collaboration_lifecycle(db_engine) -> None:
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    owner_headers = _headers(owner)
    partner_headers = _headers(partner)
    owner_id = owner["user"]["id"]
    partner_id = partner["user"]["id"]

    now = datetime.now(timezone.utc)
    week_start = datetime.combine(
        now.date() - timedelta(days=now.weekday()),
        datetime.min.time(),
        tzinfo=timezone.utc,
    )
    due_at = (week_start + timedelta(days=1, hours=12)).isoformat()

    created_response = client.post(
        "/api/v1/tasks",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "title": "此刻双人协作闭环",
            "description": "由负责人推进并交接给另一位成员验收",
            "quadrant": "Q2",
            "labels": ["工作"],
            "due_at": due_at,
        },
    )
    assert created_response.status_code == 201, created_response.text
    task = created_response.json()
    task_id = task["id"]
    workspace_id = task["workspace_id"]
    assert task["status"] == "TODO"
    assert task["current_handler_id"] == owner_id
    cursor = _assert_sync_continuity(
        client,
        owner_headers,
        partner_headers,
        after_cursor=0,
        task_id=task_id,
        expected_status="TODO",
        expected_handler_id=owner_id,
    )
    _assert_home(
        client,
        owner_headers,
        task_id=task_id,
        mine=True,
        needs_action=0,
        waiting_on_other=0,
        week_due=1,
    )
    _assert_home(
        client,
        partner_headers,
        task_id=task_id,
        mine=False,
        needs_action=0,
        waiting_on_other=0,
        week_due=1,
    )

    started_response = client.post(
        f"/api/v1/tasks/{task_id}/transition",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "target_status": "IN_PROGRESS",
            "base_status_version": task["status_version"],
        },
    )
    assert started_response.status_code == 200, started_response.text
    started = started_response.json()
    assert started["status"] == "IN_PROGRESS"
    cursor = _assert_sync_continuity(
        client,
        owner_headers,
        partner_headers,
        after_cursor=cursor,
        task_id=task_id,
        expected_status="IN_PROGRESS",
        expected_handler_id=owner_id,
    )
    _assert_home(
        client,
        owner_headers,
        task_id=task_id,
        mine=True,
        needs_action=0,
        waiting_on_other=0,
        week_due=1,
    )
    _assert_home(
        client,
        partner_headers,
        task_id=task_id,
        mine=False,
        needs_action=0,
        waiting_on_other=0,
        week_due=1,
    )

    # The current HTTP contract exposes HANDLER_TRANSFER through the
    # compatibility task PATCH; the dedicated transfer route is not present.
    transfer_response = client.patch(
        f"/api/v1/tasks/{task_id}",
        headers=owner_headers,
        json={
            "request_id": str(uuid4()),
            "changes": {
                "current_handler_id": partner_id,
                "transfer_note": "请继续跟进交付并准备验收材料",
            },
            "base_field_versions": {
                "current_handler_id": started["field_versions"]["current_handler_id"],
            },
        },
    )
    assert transfer_response.status_code == 202, transfer_response.text
    transfer_payload = transfer_response.json()
    transfer_request = transfer_payload["approval_request"]
    assert transfer_payload["pending"] is True
    assert transfer_payload["cursor"] > cursor
    assert transfer_request["request_type"] == "HANDLER_TRANSFER"
    assert transfer_request["requester_id"] == owner_id
    assert transfer_request["approver_id"] == partner_id
    assert transfer_request["proposed_changes"]["current_handler_id"] == partner_id
    assert transfer_request["proposed_changes"]["transfer_note"] == "请继续跟进交付并准备验收材料"
    cursor = _assert_sync_continuity(
        client,
        owner_headers,
        partner_headers,
        after_cursor=cursor,
        task_id=task_id,
        expected_status="IN_PROGRESS",
        expected_handler_id=owner_id,
    )
    _assert_home(
        client,
        owner_headers,
        task_id=task_id,
        mine=True,
        needs_action=0,
        waiting_on_other=1,
        week_due=1,
    )
    _assert_home(
        client,
        partner_headers,
        task_id=task_id,
        mine=False,
        needs_action=1,
        waiting_on_other=0,
        week_due=1,
    )

    transfer_approved_response = client.post(
        f"/api/v1/workspaces/{workspace_id}/approval-requests/{transfer_request['id']}/approve",
        headers=partner_headers,
        json={"request_id": str(uuid4())},
    )
    assert transfer_approved_response.status_code == 200, transfer_approved_response.text
    transfer_approved = transfer_approved_response.json()
    assert transfer_approved["approval_request"]["status"] == "APPROVED"
    assert transfer_approved["task"]["status"] == "IN_PROGRESS"
    assert transfer_approved["task"]["current_handler_id"] == partner_id
    assert transfer_approved["cursor"] > cursor
    cursor = _assert_sync_continuity(
        client,
        owner_headers,
        partner_headers,
        after_cursor=cursor,
        task_id=task_id,
        expected_status="IN_PROGRESS",
        expected_handler_id=partner_id,
    )
    _assert_home(
        client,
        owner_headers,
        task_id=task_id,
        mine=False,
        needs_action=0,
        waiting_on_other=0,
        week_due=1,
    )
    _assert_home(
        client,
        partner_headers,
        task_id=task_id,
        mine=True,
        needs_action=0,
        waiting_on_other=0,
        week_due=1,
    )

    first_review_content = "已完成交付，并核对了最终验收材料"
    review_response = client.post(
        f"/api/v1/tasks/{task_id}/transition",
        headers=partner_headers,
        json={
            "request_id": str(uuid4()),
            "target_status": "REVIEW",
            "base_status_version": transfer_approved["task"]["status_version"],
            "review_content": first_review_content,
        },
    )
    assert review_response.status_code == 202, review_response.text
    review_payload = review_response.json()
    review_task = review_payload["task"]
    review_request = review_payload["approval_request"]
    assert review_task["status"] == "REVIEW"
    assert review_task["current_handler_id"] == partner_id
    assert review_task["reviewer_user_id"] == owner_id
    assert review_request["request_type"] == "STATUS_UPDATE"
    assert review_request["proposed_changes"] == {
        "target_status": "DONE",
        "review_submission": True,
        "review_content": first_review_content,
    }
    assert review_payload["cursor"] > cursor
    cursor = _assert_sync_continuity(
        client,
        owner_headers,
        partner_headers,
        after_cursor=cursor,
        task_id=task_id,
        expected_status="REVIEW",
        expected_handler_id=partner_id,
    )
    _assert_home(
        client,
        owner_headers,
        task_id=task_id,
        mine=False,
        in_moment=False,
        needs_action=1,
        waiting_on_other=0,
        week_due=1,
    )
    _assert_home(
        client,
        partner_headers,
        task_id=task_id,
        mine=True,
        in_moment=False,
        needs_action=0,
        waiting_on_other=1,
        week_due=1,
    )

    owner_review_view = client.get(f"/api/v1/tasks/{task_id}", headers=owner_headers)
    partner_review_view = client.get(f"/api/v1/tasks/{task_id}", headers=partner_headers)
    assert owner_review_view.status_code == partner_review_view.status_code == 200
    assert owner_review_view.json()["next_step"] == {
        "kind": "ACCEPT_OR_RETURN_REVIEW",
        "label": "确认验收结果",
        "request_id": review_request["id"],
        "can_act": True,
        "actions": ["APPROVE_REVIEW", "RETURN_REVIEW"],
    }
    assert partner_review_view.json()["next_step"] == {
        "kind": "WAITING_FOR_REVIEW",
        "label": "等待对方验收",
        "request_id": review_request["id"],
        "can_act": False,
        "actions": [],
    }

    rejection_reason = "请补充最终交付时间和验收截图"
    returned_response = client.post(
        f"/api/v1/workspaces/{workspace_id}/approval-requests/{review_request['id']}/reject",
        headers=owner_headers,
        json={"request_id": str(uuid4()), "reason": rejection_reason},
    )
    assert returned_response.status_code == 200, returned_response.text
    returned = returned_response.json()
    assert returned["approval_request"]["status"] == "REJECTED"
    assert returned["approval_request"]["rejection_reason"] == rejection_reason
    assert returned["task"]["status"] == "IN_PROGRESS"
    assert returned["task"]["current_handler_id"] == partner_id
    assert returned["task"]["review_rejection_reason"] == rejection_reason
    assert returned["cursor"] > cursor
    cursor = _assert_sync_continuity(
        client,
        owner_headers,
        partner_headers,
        after_cursor=cursor,
        task_id=task_id,
        expected_status="IN_PROGRESS",
        expected_handler_id=partner_id,
    )
    _assert_home(
        client,
        owner_headers,
        task_id=task_id,
        mine=False,
        needs_action=0,
        waiting_on_other=0,
        week_due=1,
    )
    _assert_home(
        client,
        partner_headers,
        task_id=task_id,
        mine=True,
        needs_action=0,
        waiting_on_other=0,
        week_due=1,
    )
    owner_return_view = client.get(f"/api/v1/tasks/{task_id}", headers=owner_headers)
    partner_return_view = client.get(f"/api/v1/tasks/{task_id}", headers=partner_headers)
    assert owner_return_view.json()["next_step"] == {
        "kind": "NO_ACTION",
        "label": "等待负责人修改",
        "can_act": False,
        "actions": [],
    }
    assert partner_return_view.json()["next_step"] == {
        "kind": "RESUBMIT_REVIEW",
        "label": "修改后重新提交验收",
        "can_act": True,
        "actions": ["SUBMIT_REVIEW"],
    }

    second_review_content = "已补充交付时间和截图，请再次验收"
    resubmitted_response = client.post(
        f"/api/v1/tasks/{task_id}/transition",
        headers=partner_headers,
        json={
            "request_id": str(uuid4()),
            "target_status": "REVIEW",
            "base_status_version": returned["task"]["status_version"],
            "review_content": second_review_content,
        },
    )
    assert resubmitted_response.status_code == 202, resubmitted_response.text
    resubmitted = resubmitted_response.json()
    second_review_request = resubmitted["approval_request"]
    assert second_review_request["id"] != review_request["id"]
    assert second_review_request["proposed_changes"]["review_content"] == second_review_content
    assert resubmitted["task"]["status"] == "REVIEW"
    assert resubmitted["task"]["current_handler_id"] == partner_id
    assert resubmitted["task"]["reviewer_user_id"] == owner_id
    assert resubmitted["cursor"] > cursor
    cursor = _assert_sync_continuity(
        client,
        owner_headers,
        partner_headers,
        after_cursor=cursor,
        task_id=task_id,
        expected_status="REVIEW",
        expected_handler_id=partner_id,
    )
    _assert_home(
        client,
        owner_headers,
        task_id=task_id,
        mine=False,
        in_moment=False,
        needs_action=1,
        waiting_on_other=0,
        week_due=1,
    )
    _assert_home(
        client,
        partner_headers,
        task_id=task_id,
        mine=True,
        in_moment=False,
        needs_action=0,
        waiting_on_other=1,
        week_due=1,
    )

    done_response = client.post(
        f"/api/v1/workspaces/{workspace_id}/approval-requests/{second_review_request['id']}/approve",
        headers=owner_headers,
        json={"request_id": str(uuid4())},
    )
    assert done_response.status_code == 200, done_response.text
    done = done_response.json()
    assert done["approval_request"]["status"] == "APPROVED"
    assert done["approval_request"]["proposed_changes"]["review_content"] == second_review_content
    assert done["task"]["status"] == "DONE"
    assert done["task"]["current_handler_id"] == partner_id
    assert done["task"]["reviewer_user_id"] == owner_id
    assert done["cursor"] > cursor
    cursor = _assert_sync_continuity(
        client,
        owner_headers,
        partner_headers,
        after_cursor=cursor,
        task_id=task_id,
        expected_status="DONE",
        expected_handler_id=partner_id,
    )
    _assert_home(
        client,
        owner_headers,
        task_id=task_id,
        mine=False,
        in_moment=False,
        needs_action=0,
        waiting_on_other=0,
        week_due=0,
    )
    _assert_home(
        client,
        partner_headers,
        task_id=task_id,
        mine=True,
        in_moment=False,
        needs_action=0,
        waiting_on_other=0,
        week_due=0,
    )

    all_changes_response = client.get(
        "/api/v1/workspaces/current/changes?after_cursor=0",
        headers=owner_headers,
    )
    assert all_changes_response.status_code == 200, all_changes_response.text
    all_changes = all_changes_response.json()
    assert all_changes["cursor"] == cursor
    assert [item["cursor"] for item in all_changes["changes"]] == list(range(1, cursor + 1))
