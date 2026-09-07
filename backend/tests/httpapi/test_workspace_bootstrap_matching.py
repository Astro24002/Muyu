from __future__ import annotations

import pytest
from sqlalchemy.orm import Session

from app.db.enums import MembershipStatus
from app.db.models import User, Workspace, WorkspaceMembership
from app.workspaces import bootstrap_schemas
from app.workspaces.bootstrap_service import WorkspaceBootstrapService


@pytest.mark.parametrize(
    ("active_member_count", "expected"),
    [
        (0, "waiting_partner"),
        (1, "waiting_partner"),
        (2, "matched"),
        (3, "error"),
    ],
)
def test_match_status_contract_is_stable(active_member_count: int, expected: str) -> None:
    assert bootstrap_schemas.match_status_for_member_count(active_member_count) == expected


def test_match_status_rejects_a_negative_member_count() -> None:
    with pytest.raises(ValueError, match="member count cannot be negative"):
        bootstrap_schemas.match_status_for_member_count(-1)


@pytest.mark.parametrize(
    ("membership_statuses", "expected_status", "expected_member_count"),
    [
        ([], "waiting_partner", 0),
        ([MembershipStatus.ACTIVE], "waiting_partner", 1),
        ([MembershipStatus.ACTIVE, MembershipStatus.PENDING], "waiting_partner", 1),
        ([MembershipStatus.ACTIVE, MembershipStatus.ACTIVE], "matched", 2),
    ],
)
def test_bootstrap_projection_only_emits_active_members(
    db_engine,
    membership_statuses: list[MembershipStatus],
    expected_status: str,
    expected_member_count: int,
) -> None:
    with Session(db_engine) as session:
        workspace = Workspace(name="Match fixture")
        users = [
            User(phone="+15550000001", display_name="Current"),
            User(phone="+15550000002", display_name="Partner"),
        ]
        session.add(workspace)
        session.add_all(users)
        session.flush()
        for slot, status in enumerate(membership_statuses, start=1):
            session.add(
                WorkspaceMembership(
                    workspace_id=workspace.id,
                    user_id=users[slot - 1].id,
                    member_slot=slot,
                    status=status,
                )
            )
        session.flush()

        payload = WorkspaceBootstrapService(session)._workspace_payload(workspace, users[0].id)

        assert payload.match_status == expected_status
        assert payload.member_count == expected_member_count
        assert len(payload.members) == expected_member_count
        assert all(member.membership_status is MembershipStatus.ACTIVE for member in payload.members)
        assert sum(member.is_current for member in payload.members) == (1 if expected_member_count else 0)
        if expected_member_count < 2:
            assert all(member.user_id != users[1].id for member in payload.members)
