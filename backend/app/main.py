from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request, status
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text

from app.auth.routes import mobile_router, router as legacy_auth_router
from app.auth.providers.fake import FakeSmsProvider
from app.auth.providers.production import ProductionSmsProvider
from app.core.config import get_settings
from app.db.migrations import run_migrations
from app.db.session import create_database_engine
from app.httpapi.errors import register_error_handlers
from app.task.routes import router as legacy_task_router
from app.user.routes import router as legacy_user_router


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    settings = get_settings()
    engine = create_database_engine(settings.database_url)

    try:
        run_migrations(str(settings.database_url))
        with engine.connect() as connection:
            connection.execute(text("SELECT 1"))
        app.state.engine = engine
        app.state.settings = settings
        if getattr(settings, "otp_provider", "fake") == "fake":
            app.state.sms_provider = FakeSmsProvider()
        else:
            import os

            endpoint = os.environ.get("OTP_PROVIDER_URL")
            api_key = os.environ.get("OTP_PROVIDER_API_KEY")
            if not endpoint or not api_key:
                raise RuntimeError("production SMS provider requires OTP_PROVIDER_URL and OTP_PROVIDER_API_KEY")
            app.state.sms_provider = ProductionSmsProvider(endpoint, api_key)
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
        allow_headers=["Authorization", "Content-Type", "Idempotency-Key"],
    )
    app.state.ready = False
    app.state.token_manager = None
    app.state.sms_provider = None
    register_error_handlers(app)
    # Legacy routes remain registered until the explicit cutover task deletes them.
    app.include_router(legacy_auth_router)
    app.include_router(mobile_router)
    app.include_router(legacy_task_router)
    app.include_router(legacy_user_router)

    @app.get("/health/live")
    def health_live() -> dict[str, str]:
        return {"status": "live"}

    @app.get("/health/ready")
    def health_ready(request: Request) -> dict[str, str]:
        if not app.state.ready:
            raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="service is starting")
        with request.app.state.engine.connect() as connection:
            connection.execute(text("SELECT 1"))
        return {"status": "ready"}

    @app.get("/healthz", include_in_schema=False)
    def legacy_healthz(request: Request) -> dict[str, str]:
        health_ready(request)
        return {"status": "ok"}

    return app
