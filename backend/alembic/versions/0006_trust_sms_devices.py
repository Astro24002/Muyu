"""Trust devices that were previously enrolled through SMS verification.

The first release no longer waits for a second account member to approve an
Android device.  Existing non-revoked pending devices are therefore promoted
to ACTIVE, while the historical authorization records are expired in place.
"""

from collections.abc import Sequence

from alembic import op
from sqlalchemy import text


revision: str = "0006_trust_sms_devices"
down_revision: str | None = "0005_remove_task_assignees"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    bind = op.get_bind()

    # Keep revoked rows and their audit/session history untouched.  Only
    # devices that can still be used are migrated to the new trust policy.
    bind.execute(
        text(
            """
            UPDATE android_devices
               SET status = 'ACTIVE',
                   enrolled_at = COALESCE(enrolled_at, created_at),
                   updated_at = now()
             WHERE status = 'PENDING'
            """
        )
    )
    bind.execute(
        text(
            """
            UPDATE device_authorization_requests
               SET status = 'EXPIRED',
                   expires_at = LEAST(expires_at, now()),
                   updated_at = now()
             WHERE status = 'PENDING'
            """
        )
    )


def downgrade() -> None:
    # The promotion is intentionally irreversible: downgrading the migration
    # must not silently make a device read-only again or resurrect requests.
    pass
