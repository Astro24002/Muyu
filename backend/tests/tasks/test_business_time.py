from datetime import datetime, timezone

from app.core.time import BUSINESS_TIMEZONE_NAME, utc_week_bounds


def test_business_week_starts_at_monday_in_frozen_workspace_timezone() -> None:
    start, end = utc_week_bounds(datetime(2026, 9, 20, 15, 59, tzinfo=timezone.utc))

    assert BUSINESS_TIMEZONE_NAME == "Asia/Shanghai"
    assert start == datetime(2026, 9, 13, 16, 0, tzinfo=timezone.utc)
    assert end == datetime(2026, 9, 20, 16, 0, tzinfo=timezone.utc)


def test_business_week_rolls_at_local_midnight_across_utc_date() -> None:
    start, end = utc_week_bounds(datetime(2026, 9, 20, 16, 0, tzinfo=timezone.utc))

    assert start == datetime(2026, 9, 20, 16, 0, tzinfo=timezone.utc)
    assert end == datetime(2026, 9, 27, 16, 0, tzinfo=timezone.utc)
