from __future__ import annotations

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.user.models import User


class UserRepository:
    def __init__(self, session: Session) -> None:
        self.session = session

    def find_by_phone(self, phone: str) -> User | None:
        return self.session.scalar(select(User).where(User.phone == phone))

    def find_by_id(self, user_id: UUID) -> User | None:
        return self.session.get(User, user_id)

    def list_users(self) -> list[User]:
        return list(self.session.scalars(select(User).order_by(User.phone)))

    def update_profile(self, user_id: UUID, *, nickname: str, role: str) -> User | None:
        user = self.find_by_id(user_id)
        if user is None:
            return None
        user.nickname = nickname
        user.role = role
        self.session.flush()
        return user
