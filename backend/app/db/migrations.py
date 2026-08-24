from pathlib import Path
import re

from alembic import command
from alembic.config import Config


_SCHEMA_NAME = re.compile(r"^[a-z_][a-z0-9_]*$")


def run_migrations(database_url: str, *, schema: str | None = None) -> None:
    if schema is not None and _SCHEMA_NAME.fullmatch(schema) is None:
        raise ValueError("schema must contain only lowercase letters, digits, and underscores")

    backend_dir = Path(__file__).resolve().parents[2]
    config = Config(str(backend_dir / "alembic.ini"))
    config.set_main_option("script_location", str(backend_dir / "alembic"))
    config.set_main_option("sqlalchemy.url", database_url.replace("%", "%%"))
    config.attributes["schema"] = schema
    command.upgrade(config, "head")
