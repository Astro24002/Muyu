from enum import StrEnum


class UserStatus(StrEnum):
    ACTIVE = "ACTIVE"
    DISABLED = "DISABLED"


class DeviceStatus(StrEnum):
    PENDING = "PENDING"
    ACTIVE = "ACTIVE"
    REVOKED = "REVOKED"


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
    WAITING = "WAITING"
    COMPLETED = "COMPLETED"
    CANCELLED = "CANCELLED"


# Public API keeps DONE while the persisted enum remains COMPLETED for compatibility.
PUBLIC_TASK_STATUS = {
    TaskStatus.TODO: "TODO",
    TaskStatus.IN_PROGRESS: "IN_PROGRESS",
    TaskStatus.WAITING: "WAITING",
    TaskStatus.COMPLETED: "DONE",
    TaskStatus.CANCELLED: "CANCELLED",
}


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
