from __future__ import annotations

from uuid import UUID

from sqlalchemy.orm import Session

from app.db.models import WorkspaceClassification


def seed_approved_classification(
    session: Session,
    workspace_id: UUID,
    created_by: UUID,
    name: str = "工作",
) -> WorkspaceClassification:
    """Seed the approved classification used by ordinary task fixtures."""

    classification = WorkspaceClassification(
        workspace_id=workspace_id,
        name=name,
        normalized_name=name.casefold(),
        created_by=created_by,
    )
    session.add(classification)
    session.flush()
    return classification
