from __future__ import annotations

from collections.abc import Iterable
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.models import WorkspaceClassification


MAX_CLASSIFICATION_LENGTH = 5


class ClassificationError(ValueError):
    """Raised when a workspace classification cannot be created or used."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


def normalize_classification_name(value: object) -> tuple[str, str]:
    if not isinstance(value, str):
        raise ClassificationError("invalid_request", "classification name must be a string")
    name = value.strip()
    if not name:
        raise ClassificationError("invalid_request", "classification name cannot be empty")
    if len(name) > MAX_CLASSIFICATION_LENGTH:
        raise ClassificationError(
            "invalid_request",
            f"classification name must be at most {MAX_CLASSIFICATION_LENGTH} characters",
        )
    normalized = name.casefold()
    # Unicode case folding can expand a string (for example, ``ß`` becomes
    # ``ss``). Validate the persisted comparison key as well so an otherwise
    # valid-looking request cannot reach a VARCHAR(5) database error during
    # approval.
    if len(normalized) > MAX_CLASSIFICATION_LENGTH:
        raise ClassificationError(
            "invalid_request",
            f"classification name must be at most {MAX_CLASSIFICATION_LENGTH} characters after normalization",
        )
    return name, normalized


class ClassificationService:
    def __init__(self, session: Session) -> None:
        self.session = session

    def list(self, workspace_id: UUID) -> list[WorkspaceClassification]:
        return list(
            self.session.scalars(
                select(WorkspaceClassification)
                .where(WorkspaceClassification.workspace_id == workspace_id)
                .order_by(
                    WorkspaceClassification.normalized_name.asc(),
                    WorkspaceClassification.id.asc(),
                )
            ).all()
        )

    def find(self, workspace_id: UUID, name: object) -> WorkspaceClassification | None:
        _, normalized = normalize_classification_name(name)
        return self.session.scalar(
            select(WorkspaceClassification)
            .where(
                WorkspaceClassification.workspace_id == workspace_id,
                WorkspaceClassification.normalized_name == normalized,
            )
            .with_for_update()
        )

    def create_approved(
        self,
        workspace_id: UUID,
        created_by: UUID,
        name: object,
    ) -> WorkspaceClassification:
        display_name, normalized = normalize_classification_name(name)
        existing = self.session.scalar(
            select(WorkspaceClassification)
            .where(
                WorkspaceClassification.workspace_id == workspace_id,
                WorkspaceClassification.normalized_name == normalized,
            )
            .with_for_update()
        )
        if existing is not None:
            raise ClassificationError("classification_exists", "classification already exists")
        row = WorkspaceClassification(
            workspace_id=workspace_id,
            name=display_name,
            normalized_name=normalized,
            created_by=created_by,
        )
        self.session.add(row)
        self.session.flush()
        return row

    @staticmethod
    def json(row: WorkspaceClassification) -> dict[str, object]:
        return {
            "id": str(row.id),
            "workspace_id": str(row.workspace_id),
            "name": row.name,
            "created_by": str(row.created_by),
            "created_at": row.created_at.isoformat() if row.created_at else None,
        }


def normalize_classification_names(values: Iterable[object]) -> list[str]:
    result: list[str] = []
    seen: set[str] = set()
    for value in values:
        name, normalized = normalize_classification_name(value)
        if normalized in seen:
            continue
        seen.add(normalized)
        result.append(name)
    return result


def validate_active_classifications(
    session: Session,
    workspace_id: UUID,
    names: Iterable[object],
    *,
    require_one: bool = False,
) -> list[str]:
    """Normalize task classifications and verify they are approved in a workspace."""
    normalized_names = normalize_classification_names(names)
    if require_one and not normalized_names:
        raise ClassificationError(
            "invalid_request",
            "at least one approved classification is required",
        )
    if require_one and len(normalized_names) > 1:
        raise ClassificationError(
            "invalid_request",
            "a task can belong to only one classification",
        )
    if not normalized_names:
        return normalized_names
    rows = session.scalars(
        select(WorkspaceClassification).where(
            WorkspaceClassification.workspace_id == workspace_id,
            WorkspaceClassification.normalized_name.in_(
                {name.casefold() for name in normalized_names}
            ),
        )
    ).all()
    active = {row.normalized_name: row.name for row in rows}
    missing = [name for name in normalized_names if name.casefold() not in active]
    if missing:
        raise ClassificationError(
            "classification_not_found",
            f"classification is not approved: {', '.join(missing)}",
        )
    # Use the approved display spelling so task data is consistent across clients.
    return [active[name.casefold()] for name in normalized_names]


__all__ = [
    "ClassificationError",
    "ClassificationService",
    "MAX_CLASSIFICATION_LENGTH",
    "normalize_classification_name",
    "normalize_classification_names",
    "validate_active_classifications",
]
