"""Shared user display-name projection for sync responses."""

from app.db.models import User


def public_display_name(user: User) -> str:
    if user.display_name and user.display_name.strip():
        return user.display_name.strip()
    if user.phone.startswith("+86") and len(user.phone) == 14:
        return user.phone[3:]
    return user.phone
