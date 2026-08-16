from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, status
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.db.migrations import run_migrations
from app.db.session import create_database_engine
from app.user.service import seed_fixed_users


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    settings = get_settings()
    engine = create_database_engine(settings.database_url)

    try:
        run_migrations(settings.database_url)
        with Session(engine) as session:
            seed_fixed_users(session, settings.auth_password)
        app.state.engine = engine
        app.state.ready = True
        yield
    finally:
        app.state.ready = False
        engine.dispose()


def create_app() -> FastAPI:
    app = FastAPI(title="Muyu API", lifespan=lifespan)
    app.state.ready = False

    @app.get("/healthz")
    def healthz() -> dict[str, str]:
        if not app.state.ready:
            raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="service is starting")
        return {"status": "ok"}

    return app
