from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session

from app.auth.routes import router as auth_router
from app.auth.tokens import TokenManager
from app.core.config import get_settings
from app.db.migrations import run_migrations
from app.db.session import create_database_engine
from app.httpapi.errors import register_error_handlers
from app.task.routes import router as task_router
from app.user.routes import router as user_router
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
        app.state.token_manager = TokenManager(
            access_secret=settings.jwt_access_secret,
            refresh_secret=settings.jwt_refresh_secret,
            access_ttl=settings.access_token_ttl,
            refresh_ttl=settings.refresh_token_ttl,
        )
        app.state.ready = True
        yield
    finally:
        app.state.ready = False
        engine.dispose()


def create_app() -> FastAPI:
    app = FastAPI(title="Muyu API", lifespan=lifespan)
    app.add_middleware(
        CORSMiddleware,
        allow_origin_regex=r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$",
        allow_methods=["GET", "POST", "PATCH", "PUT", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type"],
    )
    app.state.ready = False
    app.state.token_manager = None
    register_error_handlers(app)
    app.include_router(auth_router)
    app.include_router(task_router)
    app.include_router(user_router)

    @app.get("/healthz")
    def healthz() -> dict[str, str]:
        if not app.state.ready:
            raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="service is starting")
        return {"status": "ok"}

    return app
