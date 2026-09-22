from __future__ import annotations

from uuid import uuid4

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.db.models import Task, TaskApprovalRequest, WorkspaceChangeLog
from .test_home_routes import _client, _headers, _ready_workspace


def _invitation(client, owner, other, *, request_id=None):
    return client.post("/api/v1/task-invitations", headers=_headers(owner), json={
        "request_id": request_id or str(uuid4()),
        "title": "整理候选名单", "quadrant": "Q2", "labels": ["工作"],
        "next_step_text": "列出三位候选人",
        "acceptance_criteria": "双方确认候选名单及联系时间",
        "target_handler_id": other["user"]["id"],
    })


def test_invitation_is_not_task_until_target_accepts(db_engine) -> None:
    client = _client(db_engine)
    owner, other = _ready_workspace(client)
    sent = _invitation(client, owner, other)
    assert sent.status_code == 202, sent.text
    request = sent.json()["approval_request"]
    assert request["request_type"] == "TASK_INVITATION"
    assert request["task_id"] is None
    assert client.get("/api/v1/tasks", headers=_headers(owner)).json() == []
    home = client.get("/api/v1/home", headers=_headers(other)).json()
    assert home["entry_counts"]["needs_me"] == 1
    assert home["entry_counts"]["due_this_week"] == 0

    accepted = client.post(
        f"/api/v1/workspaces/{request['workspace_id']}/approval-requests/{request['id']}/approve",
        headers=_headers(other), json={"request_id": str(uuid4())},
    )
    assert accepted.status_code == 200, accepted.text
    task = accepted.json()["task"]
    assert task["current_handler_id"] == other["user"]["id"]
    assert task["created_by"] == owner["user"]["id"]
    assert task["reviewer_user_id"] == owner["user"]["id"]
    assert task["acceptance_criteria"] == "双方确认候选名单及联系时间"
    assert task["status"] == "IN_PROGRESS"
    assert accepted.json()["approval_request"]["task_id"] == task["id"]
    assert [item["id"] for item in client.get("/api/v1/tasks", headers=_headers(owner)).json()] == [task["id"]]
    with Session(db_engine) as session:
        cursors = session.scalars(select(WorkspaceChangeLog.cursor).where(
            WorkspaceChangeLog.workspace_id == request["workspace_id"],
        ).order_by(WorkspaceChangeLog.cursor)).all()
        assert cursors == list(range(1, max(cursors) + 1))


def test_invitation_rejection_and_withdrawal_leave_no_task(db_engine) -> None:
    client = _client(db_engine)
    owner, other = _ready_workspace(client)
    for action, actor in (("reject", other), ("cancel", owner)):
        sent = _invitation(client, owner, other)
        assert sent.status_code == 202, sent.text
        request = sent.json()["approval_request"]
        denied = client.post(
            f"/api/v1/workspaces/{request['workspace_id']}/approval-requests/{request['id']}/{action}",
            headers=_headers(actor), json={"request_id": str(uuid4()), **({"reason": "这周没有时间"} if action == "reject" else {})},
        )
        assert denied.status_code == 200, denied.text
        assert denied.json()["approval_request"]["task_id"] is None
    with Session(db_engine) as session:
        assert session.scalar(select(func.count()).select_from(Task)) == 0
        assert session.scalar(select(func.count()).select_from(TaskApprovalRequest)) == 2


def test_invitation_requires_other_member_and_is_idempotent(db_engine) -> None:
    client = _client(db_engine)
    owner, other = _ready_workspace(client)
    request_id = str(uuid4())
    sent = _invitation(client, owner, other, request_id=request_id)
    assert sent.status_code == 202, sent.text
    replay = _invitation(client, owner, other, request_id=request_id)
    assert replay.status_code == 202, replay.text
    assert replay.json()["approval_request"]["id"] == sent.json()["approval_request"]["id"]
    self_invitation = _invitation(client, owner, owner)
    assert self_invitation.status_code in (403, 422), self_invitation.text
    with Session(db_engine) as session:
        assert session.scalar(select(func.count()).select_from(Task)) == 0
