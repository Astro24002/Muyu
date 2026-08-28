"""Idempotent cleanup for expired Web login credentials.

Run from the backend package with ``python -m app.web_login.cleanup``.  The
command only removes records outside the retention window; active sessions
are first transitioned to EXPIRED when their own TTL has elapsed.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timedelta, timezone

from sqlalchemy import delete, update
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.db.enums import ChallengeStatus, WebSessionStatus
from app.db.models import WebLoginChallenge, WebSession
from app.db.session import create_database_engine


def purge_expired_sessions(
    session: Session,
    *,
    now: datetime | None = None,
    retention_days: int = 30,
) -> int:
    """Expire stale active rows and remove old non-active history.

    The returned count includes deleted WebSession and WebLoginChallenge
    records.  The operation is safe to repeat and never deletes a row that is
    still ACTIVE at the time of the call.
    """

    current = now or datetime.now(timezone.utc)
    retention = max(1, retention_days)
    cutoff = current - timedelta(days=retention)

    # Persist the logical state transition at the real expiry timestamp so a
    # later run can remove the record once the retention window has elapsed.
    session.execute(
        update(WebSession)
        .where(
            WebSession.status == WebSessionStatus.ACTIVE,
            WebSession.expires_at <= current,
        )
        .values(
            status=WebSessionStatus.EXPIRED,
            updated_at=WebSession.expires_at,
        )
    )
    session.execute(
        update(WebLoginChallenge)
        .where(
            WebLoginChallenge.status == ChallengeStatus.PENDING,
            WebLoginChallenge.expires_at <= current,
        )
        .values(status=ChallengeStatus.EXPIRED)
    )

    session_deleted = session.execute(
        delete(WebSession).where(
            WebSession.status != WebSessionStatus.ACTIVE,
            WebSession.updated_at < cutoff,
        )
    ).rowcount or 0
    challenge_deleted = session.execute(
        delete(WebLoginChallenge).where(
            WebLoginChallenge.status.in_([
                ChallengeStatus.CONSUMED,
                ChallengeStatus.EXPIRED,
                ChallengeStatus.REVOKED,
            ]),
            WebLoginChallenge.created_at < cutoff,
        )
    ).rowcount or 0
    return int(session_deleted + challenge_deleted)


def main() -> None:
    parser = argparse.ArgumentParser(description="Purge expired Muyu web login history")
    parser.add_argument("--retention-days", type=int, default=None)
    args = parser.parse_args()
    settings = get_settings()
    engine = create_database_engine(settings.database_url)
    try:
        with Session(engine) as session:
            removed = purge_expired_sessions(
                session,
                retention_days=args.retention_days or settings.sync_retention_days,
            )
            session.commit()
        print(f"purged_records={removed}")
    finally:
        engine.dispose()


if __name__ == "__main__":
    main()
