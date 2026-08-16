from sqlalchemy import select
from sqlalchemy.orm import Session

from app.user.models import User
from app.user.service import FIXED_USER_PHONES, seed_fixed_users


def test_seed_fixed_users_is_idempotent_and_preserves_profile(db_engine) -> None:
    with Session(db_engine) as session:
        seed_fixed_users(session, "shared-password")
        users = session.scalars(select(User).order_by(User.phone)).all()

        assert [user.phone for user in users] == sorted(FIXED_USER_PHONES)
        assert len(users) == 2
        users[0].nickname = "changed nickname"
        users[0].role = "changed role"
        existing_hash = users[0].password_hash
        session.commit()

        seed_fixed_users(session, "a-different-password")
        session.refresh(users[0])
        repeated_users = session.scalars(select(User).order_by(User.phone)).all()

        assert len(repeated_users) == 2
        assert repeated_users[0].nickname == "changed nickname"
        assert repeated_users[0].role == "changed role"
        assert repeated_users[0].password_hash == existing_hash
