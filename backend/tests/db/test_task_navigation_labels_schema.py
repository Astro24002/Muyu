from __future__ import annotations

from sqlalchemy import inspect, text
from sqlalchemy.dialects.postgresql import JSONB

from app.db.enums import TaskQuadrant
from app.db.models import Task


def test_tasks_require_quadrant_and_store_labels_as_jsonb_arrays(db_engine) -> None:
    inspector = inspect(db_engine)
    columns = {column["name"]: column for column in inspector.get_columns("tasks")}

    quadrant = columns["quadrant"]
    labels = columns["labels"]
    assert quadrant["nullable"] is False
    assert labels["nullable"] is False
    assert isinstance(labels["type"], JSONB)
    assert labels["default"] is not None
    assert "[]" in str(labels["default"])

    assert Task.__table__.c.quadrant.nullable is False
    assert Task.__table__.c.quadrant.type.enum_class is TaskQuadrant
    assert Task.__table__.c.labels.nullable is False
    assert isinstance(Task.__table__.c.labels.type, JSONB)

    check_constraints = inspect(db_engine).get_check_constraints("tasks")
    check_sql = " ".join((item.get("sqltext") or "").lower() for item in check_constraints)
    assert "jsonb_typeof" in check_sql
    assert "labels" in check_sql
    assert "array" in check_sql

    with db_engine.connect() as connection:
        quadrant_values = connection.execute(
            text(
                "SELECT array_agg(e.enumlabel ORDER BY e.enumsortorder) "
                "FROM pg_type t "
                "JOIN pg_enum e ON e.enumtypid = t.oid "
                "JOIN pg_namespace n ON n.oid = t.typnamespace "
                "WHERE n.nspname = current_schema() AND t.typname = 'task_quadrant'"
            )
        ).scalar_one()
    assert quadrant_values == [item.value for item in TaskQuadrant]
