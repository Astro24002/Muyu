"""Authenticated current-user profile mutations."""

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.models import User


def public_display_name(user: User) -> str:
    """Return the user-visible name without persisting a duplicate default."""

    if user.display_name and user.display_name.strip():
        return user.display_name.strip()
    # Mobile numbers are stored in E.164 form, but Chinese users normally
    # recognise their default profile name as the familiar 11-digit number.
    if user.phone.startswith("+86") and len(user.phone) == 14:
        return user.phone[3:]
    return user.phone


class ProfileService:
    """Persist the small profile surface exposed by the mobile client."""

    def __init__(self, session: Session) -> None:
        self.session = session

    def update_display_name(
        self,
        user_id: UUID,
        display_name: str | None,
    ) -> User:
        user = self.session.scalar(select(User).where(User.id == user_id).with_for_update())
        if user is None:
            raise LookupError("user not found")
        trimmed = display_name.strip() if display_name is not None else None
        user.display_name = trimmed or None
        self.session.flush()
        return user
