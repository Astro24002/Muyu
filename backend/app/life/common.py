from __future__ import annotations

import hashlib
import json
from collections.abc import Callable
from datetime import date, datetime, timezone
from decimal import Decimal
from uuid import UUID
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.enums import ChangeAction, MembershipStatus
from app.db.models import ActivityEvent, DomainCommand, User, WorkspaceChangeLog, WorkspaceMembership
from app.db.repositories.base import Repository
from app.httpapi.errors import ApiError
from app.tasks.operations import request_fingerprint


BUSINESS_TIMEZONE = ZoneInfo("Asia/Shanghai")
MONEY_MAX_MINOR = 2_000_000_000


class LifeError(Exception):
    def __init__(self, code: str, message: str, status_code: int = 422) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.status_code = status_code


def active_member(session: Session, workspace_id: UUID, user_id: UUID) -> User:
    row = session.execute(
        select(User)
        .join(WorkspaceMembership, WorkspaceMembership.user_id == User.id)
        .where(
            WorkspaceMembership.workspace_id == workspace_id,
            WorkspaceMembership.user_id == user_id,
            WorkspaceMembership.status == MembershipStatus.ACTIVE,
        )
    ).scalar_one_or_none()
    if row is None:
        raise LifeError("workspace_access_denied", "user is not an active workspace member", 403)
    return row


def parse_money_minor(amount: object | None, amount_minor: object | None) -> int:
    if amount_minor is not None:
        if isinstance(amount_minor, bool) or not isinstance(amount_minor, int):
            raise LifeError("invalid_amount", "amount_minor must be an integer")
        minor = amount_minor
    elif amount is not None:
        try:
            raw = Decimal(str(amount).strip())
        except Exception as error:
            raise LifeError("invalid_amount", "amount must be a decimal value") from error
        if not raw.is_finite() or raw <= 0 or raw.as_tuple().exponent < -2:
            raise LifeError("invalid_amount", "amount must be greater than zero with at most two decimals")
        minor_decimal = raw * 100
        if minor_decimal != minor_decimal.to_integral_value():
            raise LifeError("invalid_amount", "amount must have at most two decimals")
        minor = int(minor_decimal)
    else:
        raise LifeError("invalid_amount", "amount or amount_minor is required")
    if minor <= 0 or minor > MONEY_MAX_MINOR:
        raise LifeError("invalid_amount", "amount is outside the supported range")
    return minor


def format_money_minor(amount_minor: int) -> str:
    return f"{Decimal(amount_minor) / Decimal(100):.2f}"


def parse_date(value: object, field: str) -> date:
    if isinstance(value, date) and not isinstance(value, datetime):
        return value
    if isinstance(value, str):
        try:
            return date.fromisoformat(value)
        except ValueError as error:
            raise LifeError("invalid_request", f"{field} must be an ISO calendar date") from error
    raise LifeError("invalid_request", f"{field} must be an ISO calendar date")


def now_utc(now: Callable[[], datetime] | None = None) -> datetime:
    value = now() if now is not None else datetime.now(timezone.utc)
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def workspace_today(now: Callable[[], datetime] | None = None) -> date:
    return now_utc(now).astimezone(BUSINESS_TIMEZONE).date()


def allocate_resource_cursor(
    session: Session,
    workspace_id: UUID,
    resource_type: str,
    resource_id: UUID,
    action: ChangeAction,
    request_id: UUID,
) -> int:
    cursor = Repository(session).allocate_workspace_cursor(workspace_id)
    session.add(
        WorkspaceChangeLog(
            workspace_id=workspace_id,
            cursor=cursor,
            resource_type=resource_type,
            resource_id=resource_id,
            action=action,
            operation_id=request_id,
        )
    )
    return cursor


def record_activity(
    session: Session,
    workspace_id: UUID,
    actor_user_id: UUID,
    event_type: str,
    payload: dict[str, object],
    request_id: UUID,
) -> ActivityEvent:
    event = ActivityEvent(
        workspace_id=workspace_id,
        actor_user_id=actor_user_id,
        event_type=event_type,
        payload=payload,
        request_id=request_id,
    )
    session.add(event)
    session.flush()
    return event


def get_command(
    session: Session,
    workspace_id: UUID,
    actor_user_id: UUID,
    request_id: UUID,
    route: str,
    body: dict[str, object],
) -> DomainCommand | None:
    fingerprint = request_fingerprint(route, body)
    command = session.scalar(
        select(DomainCommand)
        .where(
            DomainCommand.workspace_id == workspace_id,
            DomainCommand.request_id == request_id,
        )
        .with_for_update()
    )
    if command is not None:
        if command.actor_user_id != actor_user_id or command.fingerprint != fingerprint:
            raise LifeError("idempotency_key_reused", "request id belongs to another command", 409)
    return command


def save_command(
    session: Session,
    workspace_id: UUID,
    actor_user_id: UUID,
    request_id: UUID,
    resource_type: str,
    resource_id: UUID,
    cursor: int,
    route: str,
    body: dict[str, object],
) -> DomainCommand:
    command = DomainCommand(
        workspace_id=workspace_id,
        request_id=request_id,
        actor_user_id=actor_user_id,
        resource_type=resource_type,
        resource_id=resource_id,
        fingerprint=request_fingerprint(route, body),
        cursor=cursor,
    )
    session.add(command)
    session.flush()
    return command


def as_api_error(error: LifeError) -> ApiError:
    return ApiError(error.status_code, error.code, error.message)


def json_body(values: dict[str, object]) -> dict[str, object]:
    """Normalize UUID/date/enum values before fingerprinting a command."""
    return json.loads(json.dumps(values, default=lambda value: value.isoformat() if hasattr(value, "isoformat") else str(value), sort_keys=True))
