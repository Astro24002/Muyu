from __future__ import annotations

from datetime import datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo


# The first release has one frozen Workspace business timezone. Persisted
# timestamps remain UTC; this zone is used only for calendar and week rules.
BUSINESS_TIMEZONE_NAME = "Asia/Shanghai"
BUSINESS_TIMEZONE = ZoneInfo(BUSINESS_TIMEZONE_NAME)


def utc_week_bounds(now: datetime) -> tuple[datetime, datetime]:
    """Return Monday 00:00 and the following Monday as UTC instants."""
    normalized = now if now.tzinfo is not None else now.replace(tzinfo=timezone.utc)
    local = normalized.astimezone(BUSINESS_TIMEZONE)
    local_start = datetime.combine(
        local.date() - timedelta(days=local.weekday()),
        time.min,
        tzinfo=BUSINESS_TIMEZONE,
    )
    return (
        local_start.astimezone(timezone.utc),
        (local_start + timedelta(days=7)).astimezone(timezone.utc),
    )
