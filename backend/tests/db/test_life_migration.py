from __future__ import annotations

from alembic import command
from alembic.config import Config
from pathlib import Path
from sqlalchemy import inspect, text


def _config(database_url: str, schema: str) -> Config:
    backend_dir = Path(__file__).resolve().parents[2]
    config = Config(str(backend_dir / "alembic.ini"))
    config.set_main_option("script_location", str(backend_dir / "alembic"))
    config.set_main_option("sqlalchemy.url", database_url.replace("%", "%%"))
    config.attributes["schema"] = schema
    return config


def test_life_schema_reversible_with_existing_task_data(db_engine, database_url: str) -> None:
    with db_engine.connect() as connection:
        schema = connection.scalar(text("SELECT current_schema()"))
    inspector = inspect(db_engine)
    assert "ledger_entries" in inspector.get_table_names()
    assert "source_key" in {column["name"] for column in inspector.get_columns("tasks")}
    config = _config(database_url, schema)
    command.downgrade(config, "0015_task_next_step_text")
    inspector = inspect(db_engine)
    assert "ledger_entries" not in inspector.get_table_names()
    assert "source_key" not in {column["name"] for column in inspector.get_columns("tasks")}
    command.upgrade(config, "head")
    inspector = inspect(db_engine)
    assert "ledger_entries" in inspector.get_table_names()
    assert "source_key" in {column["name"] for column in inspector.get_columns("tasks")}
