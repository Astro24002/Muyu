from enum import StrEnum


class UserStatus(StrEnum):
    ACTIVE = "ACTIVE"
    DISABLED = "DISABLED"


class DeviceStatus(StrEnum):
    PENDING = "PENDING"
    ACTIVE = "ACTIVE"
    REVOKED = "REVOKED"


class PublicDeviceStatus(StrEnum):
    """Stable device status values exposed outside the persistence layer."""

    UNVERIFIED = "UNVERIFIED"
    VERIFIED = "VERIFIED"
    REVOKED = "REVOKED"


class BootstrapState(StrEnum):
    """Derived workspace onboarding states returned by the bootstrap API."""

    NEEDS_PARTNER = "NEEDS_PARTNER"
    WAITING_FOR_PARTNER = "WAITING_FOR_PARTNER"
    INVITED = "INVITED"
    READY = "READY"


class WorkspaceStatus(StrEnum):
    ACTIVE = "ACTIVE"
    ARCHIVED = "ARCHIVED"


class MembershipStatus(StrEnum):
    PENDING = "PENDING"
    ACTIVE = "ACTIVE"
    REVOKED = "REVOKED"
    LEFT = "LEFT"


class InviteStatus(StrEnum):
    PENDING = "PENDING"
    ACCEPTED = "ACCEPTED"
    EXPIRED = "EXPIRED"
    REVOKED = "REVOKED"


class ApprovalStatus(StrEnum):
    PENDING = "PENDING"
    APPROVED = "APPROVED"
    EXPIRED = "EXPIRED"
    REVOKED = "REVOKED"
    REJECTED = "REJECTED"


class WebSessionStatus(StrEnum):
    ACTIVE = "ACTIVE"
    REVOKED = "REVOKED"
    EXPIRED = "EXPIRED"


class TaskStatus(StrEnum):
    TODO = "TODO"
    IN_PROGRESS = "IN_PROGRESS"
    BLOCKED = "BLOCKED"
    REVIEW = "REVIEW"
    DONE = "DONE"
    CANCELLED = "CANCELLED"


class TaskQuadrant(StrEnum):
    Q1 = "Q1"
    Q2 = "Q2"
    Q3 = "Q3"
    Q4 = "Q4"


class TaskApprovalRequestType(StrEnum):
    TASK_INVITATION = "TASK_INVITATION"
    TASK_UPDATE = "TASK_UPDATE"
    QUADRANT_UPDATE = "QUADRANT_UPDATE"
    STATUS_UPDATE = "STATUS_UPDATE"
    TASK_DELETE = "TASK_DELETE"
    TASK_RESTORE = "TASK_RESTORE"
    COMMENT_DELETE = "COMMENT_DELETE"
    HANDLER_TRANSFER = "HANDLER_TRANSFER"
    CLASSIFICATION_CREATE = "CLASSIFICATION_CREATE"


class TaskApprovalRequestStatus(StrEnum):
    PENDING = "PENDING"
    APPROVED = "APPROVED"
    REJECTED = "REJECTED"
    CONFLICTED = "CONFLICTED"
    CANCELLED = "CANCELLED"


class LedgerEntryType(StrEnum):
    EXPENSE = "EXPENSE"
    INCOME = "INCOME"


class HabitFrequency(StrEnum):
    DAILY = "DAILY"
    WEEKLY = "WEEKLY"
    MONTHLY = "MONTHLY"


class HabitStatus(StrEnum):
    ACTIVE = "ACTIVE"
    PAUSED = "PAUSED"
    DELETED = "DELETED"


class AnniversaryKind(StrEnum):
    ANNIVERSARY = "ANNIVERSARY"
    BIRTHDAY = "BIRTHDAY"
    IMPORTANT_DAY = "IMPORTANT_DAY"


# The public status names are the canonical persisted status names.
PUBLIC_TASK_STATUS = {status: status.value for status in TaskStatus}


class ChangeAction(StrEnum):
    CREATED = "CREATED"
    UPDATED = "UPDATED"
    DELETED = "DELETED"
    RESTORED = "RESTORED"


class OperationType(StrEnum):
    CREATED = "CREATED"
    UPDATED = "UPDATED"
    STATUS_CHANGED = "STATUS_CHANGED"
    HANDLER_CHANGED = "HANDLER_CHANGED"
    DELETED = "DELETED"
    RESTORED = "RESTORED"
    COMMENTED = "COMMENTED"
    DELAYED = "DELAYED"
    CONFLICT_RESOLVED = "CONFLICT_RESOLVED"
    CONFLICT_CREATED = "CONFLICT_CREATED"


class ConflictStatus(StrEnum):
    OPEN = "OPEN"
    RESOLVED = "RESOLVED"
    REJECTED = "REJECTED"


class Resolution(StrEnum):
    KEEP_CURRENT = "KEEP_CURRENT"
    ACCEPT_PROPOSED = "ACCEPT_PROPOSED"


class RecurrenceStatus(StrEnum):
    ACTIVE = "ACTIVE"
    PAUSED = "PAUSED"
    CANCELLED = "CANCELLED"


class ChallengeStatus(StrEnum):
    PENDING = "PENDING"
    APPROVED = "APPROVED"
    CONSUMED = "CONSUMED"
    EXPIRED = "EXPIRED"
    REVOKED = "REVOKED"
