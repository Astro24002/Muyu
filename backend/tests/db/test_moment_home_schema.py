from __future__ import annotations

from pathlib import Path

from alembic import command
from alembic.config import Config
from sqlalchemy import inspect, text

from app.db.models import Task


_EXPECTED_TASK_INDEXES = {
    "ix_tasks_home_current_handler": (
        "workspace_id",
        "deleted_at",
        "status",
        "current_handler_id",
        "due_at",
    ),
    "ix_tasks_home_reviewer": (
        "workspace_id",
        "deleted_at",
        "status",
        "reviewer_user_id",
        "due_at",
    ),
}


def _config(database_url: str, schema: str) -> Config:
    backend_dir = Path(__file__).resolve().parents[2]
    config = Config(str(backend_dir / "alembic.ini"))
    config.set_main_option("script_location", str(backend_dir / "alembic"))
    config.set_main_option("sqlalchemy.url", database_url.replace("%", "%%"))
    config.attributes["schema"] = schema
    return config


def _schema(engine) -> str:
    with engine.connect() as connection:
        return connection.scalar(text("SELECT current_schema()"))


def _task_indexes(engine) -> dict[str, tuple[str, ...]]:
    return {
        index["name"]: tuple(index["column_names"])
        for index in inspect(engine).get_indexes("tasks")
    }


def test_home_task_indexes_match_orm_and_are_reversible(db_engine, database_url: str) -> None:
    assert {
        index.name: tuple(column.name for column in index.columns)
        for index in Task.__table__.indexes
        if index.name in _EXPECTED_TASK_INDEXES
    } == _EXPECTED_TASK_INDEXES
    assert _EXPECTED_TASK_INDEXES.items() <= _task_indexes(db_engine).items()

    config = _config(database_url, _schema(db_engine))
    command.downgrade(config, "0013_remove_default_class")
    assert _EXPECTED_TASK_INDEXES.keys().isdisjoint(_task_indexes(db_engine))

    command.upgrade(config, "head")
    assert _EXPECTED_TASK_INDEXES.items() <= _task_indexes(db_engine).items()
