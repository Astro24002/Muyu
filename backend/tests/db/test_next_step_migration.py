from __future__ import annotations

from pathlib import Path

from alembic import command
from alembic.config import Config
from sqlalchemy import inspect, text


def _config(database_url: str, schema: str) -> Config:
    backend_dir = Path(__file__).resolve().parents[2]
    config = Config(str(backend_dir / "alembic.ini"))
    config.set_main_option("script_location", str(backend_dir / "alembic"))
    config.set_main_option("sqlalchemy.url", database_url.replace("%", "%%"))
    config.attributes["schema"] = schema
    return config


def _task_columns(db_engine) -> set[str]:
    return {column["name"] for column in inspect(db_engine).get_columns("tasks")}


def test_next_step_column_is_reversible(db_engine, database_url: str) -> None:
    with db_engine.connect() as connection:
        schema = connection.scalar(text("SELECT current_schema()"))

    assert "next_step_text" in _task_columns(db_engine)

    config = _config(database_url, schema)
    command.downgrade(config, "0014_moment_home_indexes")
    assert "next_step_text" not in _task_columns(db_engine)

    command.upgrade(config, "head")
    assert "next_step_text" in _task_columns(db_engine)
