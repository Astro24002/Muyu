from __future__ import annotations

from datetime import datetime, timezone

import bcrypt
from sqlalchemy import insert
from sqlalchemy.dialects.postgresql import insert as postgres_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.orm import Session

from app.user.models import User

FIXED_USER_PHONES = ("15028180169", "15068128726")
_FIXED_USER_DEFAULTS = (
    {"phone": FIXED_USER_PHONES[0], "nickname": "用户 A", "avatar_key": "user-a", "role": "男方"},
    {"phone": FIXED_USER_PHONES[1], "nickname": "用户 B", "avatar_key": "user-b", "role": "女方"},
)


def seed_fixed_users(session: Session, auth_password: str) -> None:
    now = datetime.now(timezone.utc)
    for defaults in _FIXED_USER_DEFAULTS:
        if session.query(User).filter_by(phone=defaults["phone"]).one_or_none() is not None:
            continue
        values = {
            **defaults,
            "password_hash": bcrypt.hashpw(auth_password.encode(), bcrypt.gensalt()).decode(),
            "created_at": now,
            "updated_at": now,
        }
        dialect = session.get_bind().dialect.name
        if dialect == "postgresql":
            statement = postgres_insert(User).values(**values).on_conflict_do_nothing(index_elements=["phone"])
        elif dialect == "sqlite":
            statement = sqlite_insert(User).values(**values).on_conflict_do_nothing(index_elements=["phone"])
        else:
            statement = insert(User).values(**values)
        session.execute(statement)
    session.commit()
