from sqlalchemy import create_engine
from sqlalchemy.engine import Engine, URL, make_url


def create_database_engine(database_url: str | URL) -> Engine:
    url = make_url(str(database_url))
    if url.get_backend_name() != "postgresql":
        raise ValueError("DATABASE_URL must use PostgreSQL")
    return create_engine(url, pool_pre_ping=True)
