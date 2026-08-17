from datetime import datetime, timezone

from sqlalchemy import DateTime, TypeDecorator


class UTCDateTime(TypeDecorator[datetime]):
    """Keep UTC-aware datetimes consistent across PostgreSQL and SQLite tests."""

    impl = DateTime
    cache_ok = True

    def load_dialect_impl(self, dialect):
        return dialect.type_descriptor(DateTime(timezone=True))

    def process_bind_param(self, value: datetime | None, dialect):
        if value is None:
            return None
        normalized = value if value.tzinfo is not None else value.replace(tzinfo=timezone.utc)
        if dialect.name == "sqlite":
            return normalized.astimezone(timezone.utc).replace(tzinfo=None)
        return normalized.astimezone(timezone.utc)

    def process_result_value(self, value: datetime | None, _dialect):
        if value is None:
            return None
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)
