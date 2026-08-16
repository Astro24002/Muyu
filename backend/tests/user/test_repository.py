from sqlalchemy.orm import Session

from app.user.repository import UserRepository
from app.user.service import seed_fixed_users


def test_repository_finds_users_by_phone_and_lists_stably(db_engine) -> None:
    with Session(db_engine) as session:
        seed_fixed_users(session, "shared-password")
        repository = UserRepository(session)

        first = repository.find_by_phone("15028180169")
        second = repository.find_by_phone("15068128726")
        users = repository.list_users()

        assert first is not None
        assert second is not None
        assert [user.phone for user in users] == sorted(["15028180169", "15068128726"])


def test_repository_updates_only_mutable_profile_fields(db_engine) -> None:
    with Session(db_engine) as session:
        seed_fixed_users(session, "shared-password")
        repository = UserRepository(session)
        user = repository.find_by_phone("15028180169")
        assert user is not None
        original_phone = user.phone
        original_avatar = user.avatar_key

        updated = repository.update_profile(user.id, nickname="new", role="partner")

        assert updated.nickname == "new"
        assert updated.role == "partner"
        assert updated.phone == original_phone
        assert updated.avatar_key == original_avatar
