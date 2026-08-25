from __future__ import annotations

from datetime import datetime
from typing import Any
from uuid import UUID, uuid4

from sqlalchemy import Boolean, CheckConstraint, DateTime, ForeignKey, Integer, LargeBinary, String, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import ARRAY, JSONB, UUID as PGUUID
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
from sqlalchemy.types import Enum as SAEnum

from app.db.enums import (
    ApprovalStatus,
    ChangeAction,
    ChallengeStatus,
    ConflictStatus,
    DeviceStatus,
    InviteStatus,
    MembershipStatus,
    OperationType,
    RecurrenceStatus,
    Resolution,
    TaskStatus,
    UserStatus,
    WebSessionStatus,
    WorkspaceStatus,
)


class Base(DeclarativeBase):
    pass


def _enum(enum_type: type) -> SAEnum:
    return SAEnum(enum_type, name=_snake(enum_type.__name__), native_enum=True, validate_strings=True)


def _snake(value: str) -> str:
    return "".join(f"_{char.lower()}" if char.isupper() else char for char in value).lstrip("_")


def _id() -> Mapped[UUID]:
    return mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)


def _created() -> Mapped[datetime]:
    return mapped_column(DateTime(timezone=True), nullable=False, server_default="now()")


class User(Base):
    __tablename__ = "users"

    id = _id()
    phone: Mapped[str] = mapped_column(String(20), nullable=False)
    display_name: Mapped[str | None] = mapped_column(String(120))
    status: Mapped[UserStatus] = mapped_column(_enum(UserStatus), nullable=False, default=UserStatus.ACTIVE, server_default="ACTIVE")
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at = _created()
    updated_at = _created()


class AndroidDevice(Base):
    __tablename__ = "android_devices"

    id = _id()
    user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    public_key_der: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    fingerprint: Mapped[str | None] = mapped_column(String(128))
    label: Mapped[str | None] = mapped_column(String(120))
    platform: Mapped[str] = mapped_column(String(32), nullable=False, default="ANDROID", server_default="ANDROID")
    status: Mapped[DeviceStatus] = mapped_column(_enum(DeviceStatus), nullable=False, default=DeviceStatus.PENDING, server_default="PENDING")
    enrolled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at = _created()
    updated_at = _created()


class MobileSession(Base):
    __tablename__ = "mobile_sessions"

    id = _id()
    user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    device_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("android_devices.id", ondelete="CASCADE"), nullable=False)
    refresh_token_digest: Mapped[str] = mapped_column(String(128), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at = _created()
    updated_at = _created()


class Workspace(Base):
    __tablename__ = "workspaces"

    id = _id()
    status: Mapped[WorkspaceStatus] = mapped_column(_enum(WorkspaceStatus), nullable=False, default=WorkspaceStatus.ACTIVE, server_default="ACTIVE")
    name: Mapped[str | None] = mapped_column(String(160))
    created_at = _created()
    updated_at = _created()


class WorkspaceMembership(Base):
    __tablename__ = "workspace_memberships"
    __table_args__ = (CheckConstraint("member_slot IN (1, 2)", name="ck_workspace_member_slot"),)

    id = _id()
    workspace_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("workspaces.id", ondelete="CASCADE"), nullable=False)
    user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    member_slot: Mapped[int] = mapped_column(Integer, nullable=False)
    status: Mapped[MembershipStatus] = mapped_column(_enum(MembershipStatus), nullable=False, default=MembershipStatus.PENDING, server_default="PENDING")
    joined_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at = _created()
    updated_at = _created()


class WorkspaceInvite(Base):
    __tablename__ = "workspace_invites"

    id = _id()
    workspace_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("workspaces.id", ondelete="CASCADE"), nullable=False)
    inviter_user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)
    invited_phone: Mapped[str] = mapped_column(String(20), nullable=False)
    status: Mapped[InviteStatus] = mapped_column(_enum(InviteStatus), nullable=False, default=InviteStatus.PENDING, server_default="PENDING")
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    accepted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at = _created()
    updated_at = _created()


class DeviceAuthorizationRequest(Base):
    __tablename__ = "device_authorization_requests"

    id = _id()
    workspace_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("workspaces.id", ondelete="CASCADE"), nullable=False)
    candidate_device_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("android_devices.id", ondelete="CASCADE"), nullable=False)
    approving_device_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), ForeignKey("android_devices.id", ondelete="RESTRICT"))
    status: Mapped[ApprovalStatus] = mapped_column(_enum(ApprovalStatus), nullable=False, default=ApprovalStatus.PENDING, server_default="PENDING")
    safety_code_digest: Mapped[str] = mapped_column(String(128), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    approved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at = _created()
    updated_at = _created()


class DeviceAuthorizationChallenge(Base):
    __tablename__ = "device_authorization_challenges"

    id = _id()
    request_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("device_authorization_requests.id", ondelete="CASCADE"), nullable=False)
    # Challenge nonces are supplied by the service; avoid a textual bytea
    # default that different PostgreSQL drivers interpret inconsistently.
    nonce: Mapped[bytes] = mapped_column(LargeBinary, nullable=False, default=lambda: b"")
    challenge_digest: Mapped[str] = mapped_column(String(128), nullable=False)
    signature: Mapped[bytes | None] = mapped_column(LargeBinary)
    status: Mapped[ChallengeStatus] = mapped_column(_enum(ChallengeStatus), nullable=False, default=ChallengeStatus.PENDING, server_default="PENDING")
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    consumed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at = _created()


class RecoveryRequest(Base):
    __tablename__ = "recovery_requests"

    id = _id()
    workspace_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("workspaces.id", ondelete="CASCADE"), nullable=False)
    requester_user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)
    approver_user_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="RESTRICT"))
    requester_device_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), ForeignKey("android_devices.id", ondelete="RESTRICT"))
    approver_device_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), ForeignKey("android_devices.id", ondelete="RESTRICT"))
    status: Mapped[ApprovalStatus] = mapped_column(_enum(ApprovalStatus), nullable=False, default=ApprovalStatus.PENDING, server_default="PENDING")
    audit_parent_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    approved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at = _created()
    updated_at = _created()


class PhoneChangeRequest(Base):
    __tablename__ = "phone_change_requests"

    id = _id()
    user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    workspace_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), ForeignKey("workspaces.id", ondelete="SET NULL"))
    old_phone: Mapped[str] = mapped_column(String(20), nullable=False)
    new_phone: Mapped[str] = mapped_column(String(20), nullable=False)
    approver_user_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="RESTRICT"))
    status: Mapped[ApprovalStatus] = mapped_column(_enum(ApprovalStatus), nullable=False, default=ApprovalStatus.PENDING, server_default="PENDING")
    audit_parent_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at = _created()
    updated_at = _created()


class SmsVerificationChallenge(Base):
    __tablename__ = "sms_verification_challenges"

    id = _id()
    phone: Mapped[str] = mapped_column(String(20), nullable=False)
    code_digest: Mapped[str] = mapped_column(String(128), nullable=False)
    attempt_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    request_ip_digest: Mapped[str | None] = mapped_column(String(128))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    consumed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at = _created()


class WebLoginChallenge(Base):
    __tablename__ = "web_login_challenges"

    id = _id()
    browser_proof_digest: Mapped[str] = mapped_column(String(128), nullable=False)
    scan_nonce_digest: Mapped[str] = mapped_column(String(128), nullable=False)
    safety_code_digest: Mapped[str] = mapped_column(String(128), nullable=False)
    origin: Mapped[str] = mapped_column(String(512), nullable=False)
    user_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"))
    workspace_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), ForeignKey("workspaces.id", ondelete="CASCADE"))
    approving_device_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), ForeignKey("android_devices.id", ondelete="RESTRICT"))
    approved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    status: Mapped[ChallengeStatus] = mapped_column(_enum(ChallengeStatus), nullable=False, default=ChallengeStatus.PENDING, server_default="PENDING")
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    consumed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at = _created()


class WebSession(Base):
    __tablename__ = "web_sessions"

    id = _id()
    user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    workspace_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("workspaces.id", ondelete="CASCADE"), nullable=False)
    approving_device_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("android_devices.id", ondelete="RESTRICT"), nullable=False)
    session_digest: Mapped[str] = mapped_column(String(128), nullable=False)
    status: Mapped[WebSessionStatus] = mapped_column(_enum(WebSessionStatus), nullable=False, default=WebSessionStatus.ACTIVE, server_default="ACTIVE")
    origin: Mapped[str | None] = mapped_column(String(512))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at = _created()
    updated_at = _created()


class IdempotencyRecord(Base):
    __tablename__ = "idempotency_records"
    __table_args__ = (UniqueConstraint("workspace_id", "request_id", name="uq_idempotency_workspace_request"),)

    id = _id()
    workspace_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("workspaces.id", ondelete="CASCADE"), nullable=False)
    request_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), nullable=False)
    actor_user_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"))
    route: Mapped[str] = mapped_column(String(255), nullable=False)
    request_fingerprint: Mapped[str] = mapped_column(String(128), nullable=False)
    response_status: Mapped[int] = mapped_column(Integer, nullable=False)
    response_body: Mapped[str] = mapped_column(Text, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    created_at = _created()


class WorkspaceCursor(Base):
    __tablename__ = "workspace_cursors"

    workspace_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("workspaces.id", ondelete="CASCADE"), primary_key=True)
    next_cursor: Mapped[int] = mapped_column(Integer, nullable=False, default=1, server_default="1")
    updated_at = _created()


class WorkspaceChangeLog(Base):
    __tablename__ = "workspace_change_log"
    __table_args__ = (UniqueConstraint("workspace_id", "cursor", name="uq_workspace_change_cursor"),)

    id = _id()
    workspace_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("workspaces.id", ondelete="CASCADE"), nullable=False)
    cursor: Mapped[int] = mapped_column(Integer, nullable=False)
    resource_type: Mapped[str] = mapped_column(String(64), nullable=False)
    resource_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), nullable=False)
    action: Mapped[ChangeAction] = mapped_column(_enum(ChangeAction), nullable=False)
    operation_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True))
    created_at = _created()


class Task(Base):
    __tablename__ = "tasks"
    __table_args__ = (
        CheckConstraint("version > 0", name="ck_tasks_version_positive"),
        CheckConstraint("lifecycle_version > 0", name="ck_tasks_lifecycle_version_positive"),
    )

    id = _id()
    workspace_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("workspaces.id", ondelete="CASCADE"), nullable=False)
    parent_task_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), ForeignKey("tasks.id", ondelete="RESTRICT"))
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False, default="", server_default="")
    status: Mapped[TaskStatus] = mapped_column(_enum(TaskStatus), nullable=False, default=TaskStatus.TODO, server_default="TODO")
    current_handler_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="RESTRICT"))
    blocked_reason: Mapped[str | None] = mapped_column(Text)
    blocked_since: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    resume_handler_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="RESTRICT"))
    waiting_for_user_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="RESTRICT"))
    planned_start_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    due_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    estimated_minutes: Mapped[int | None] = mapped_column(Integer)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_by: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)
    recurring_task_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), ForeignKey("tasks.id", ondelete="SET NULL"))
    version: Mapped[int] = mapped_column(Integer, nullable=False, default=1, server_default="1")
    field_versions: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False, default=dict, server_default="{}")
    lifecycle_version: Mapped[int] = mapped_column(Integer, nullable=False, default=1, server_default="1")
    status_version: Mapped[int] = mapped_column(Integer, nullable=False, default=1, server_default="1")
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at = _created()
    updated_at = _created()


class TaskAssignee(Base):
    __tablename__ = "task_assignees"
    task_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("tasks.id", ondelete="CASCADE"), primary_key=True)
    user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)


class TaskUserPosition(Base):
    __tablename__ = "task_user_positions"
    user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    task_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("tasks.id", ondelete="CASCADE"), primary_key=True)
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    updated_at = _created()


class TaskOperation(Base):
    __tablename__ = "task_operations"
    __table_args__ = (UniqueConstraint("workspace_id", "request_id", name="uq_task_operation_request"),)

    id = _id()
    workspace_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("workspaces.id", ondelete="CASCADE"), nullable=False)
    task_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("tasks.id", ondelete="RESTRICT"), nullable=False)
    actor_user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)
    actor_device_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), ForeignKey("android_devices.id", ondelete="RESTRICT"))
    web_session_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), ForeignKey("web_sessions.id", ondelete="RESTRICT"))
    request_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), nullable=False)
    operation_type: Mapped[OperationType] = mapped_column(_enum(OperationType), nullable=False)
    before_state: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
    after_state: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
    base_versions: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
    resulting_versions: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
    cursor: Mapped[int] = mapped_column(Integer, nullable=False)
    created_at = _created()


class TaskConflict(Base):
    __tablename__ = "task_conflicts"

    id = _id()
    workspace_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("workspaces.id", ondelete="CASCADE"), nullable=False)
    task_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("tasks.id", ondelete="RESTRICT"), nullable=False)
    target: Mapped[str] = mapped_column(String(64), nullable=False)
    base_value: Mapped[Any | None] = mapped_column(JSONB)
    current_value: Mapped[Any | None] = mapped_column(JSONB)
    proposed_value: Mapped[Any | None] = mapped_column(JSONB)
    base_version: Mapped[int] = mapped_column(Integer, nullable=False)
    current_version: Mapped[int] = mapped_column(Integer, nullable=False)
    request_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), nullable=False)
    status: Mapped[ConflictStatus] = mapped_column(_enum(ConflictStatus), nullable=False, default=ConflictStatus.OPEN, server_default="OPEN")
    resolved_by: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="RESTRICT"))
    resolution: Mapped[Resolution | None] = mapped_column(_enum(Resolution))
    created_at = _created()
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class TaskComment(Base):
    __tablename__ = "task_comments"

    id = _id()
    workspace_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("workspaces.id", ondelete="CASCADE"), nullable=False)
    task_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("tasks.id", ondelete="RESTRICT"), nullable=False)
    author_user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    created_at = _created()


class DelayRecord(Base):
    __tablename__ = "delay_records"

    id = _id()
    workspace_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("workspaces.id", ondelete="CASCADE"), nullable=False)
    task_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("tasks.id", ondelete="RESTRICT"), nullable=False)
    actor_user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)
    original_due_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    new_due_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    delayed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    delay_duration_minutes: Mapped[int] = mapped_column(Integer, nullable=False)
    reason: Mapped[str] = mapped_column(String(50), nullable=False)
    note: Mapped[str | None] = mapped_column(Text)
    created_at = _created()


class ImportantDate(Base):
    __tablename__ = "important_dates"

    id = _id()
    workspace_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("workspaces.id", ondelete="CASCADE"), nullable=False)
    task_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), ForeignKey("tasks.id", ondelete="SET NULL"))
    label: Mapped[str] = mapped_column(String(160), nullable=False)
    starts_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    ends_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_by: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at = _created()
    updated_at = _created()


class RecurrenceRule(Base):
    __tablename__ = "recurrence_rules"

    id = _id()
    workspace_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("workspaces.id", ondelete="CASCADE"), nullable=False)
    task_template_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("tasks.id", ondelete="RESTRICT"), nullable=False)
    rule: Mapped[str] = mapped_column(String(255), nullable=False)
    status: Mapped[RecurrenceStatus] = mapped_column(_enum(RecurrenceStatus), nullable=False, default=RecurrenceStatus.ACTIVE, server_default="ACTIVE")
    next_run_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_by: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)
    created_at = _created()
    updated_at = _created()


class TaskStatusHistory(Base):
    __tablename__ = "task_status_history"
    id = _id()
    task_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("tasks.id", ondelete="CASCADE"), nullable=False)
    from_status: Mapped[TaskStatus | None] = mapped_column(_enum(TaskStatus))
    to_status: Mapped[TaskStatus] = mapped_column(_enum(TaskStatus), nullable=False)
    changed_by: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)
    changed_at = _created()


class TaskHandlerHistory(Base):
    __tablename__ = "task_handler_history"
    id = _id()
    task_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("tasks.id", ondelete="CASCADE"), nullable=False)
    from_user_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="RESTRICT"))
    to_user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)
    changed_by: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)
    changed_at = _created()


class ActivityEvent(Base):
    __tablename__ = "activity_events"
    id = _id()
    workspace_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("workspaces.id", ondelete="CASCADE"), nullable=False)
    task_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), ForeignKey("tasks.id", ondelete="SET NULL"))
    actor_user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="RESTRICT"), nullable=False)
    actor_device_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), ForeignKey("android_devices.id", ondelete="RESTRICT"))
    web_session_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), ForeignKey("web_sessions.id", ondelete="RESTRICT"))
    event_type: Mapped[str] = mapped_column(String(100), nullable=False)
    payload: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False, default=dict, server_default="{}")
    request_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True))
    created_at = _created()


__all__ = [name for name in globals() if not name.startswith("_")]
