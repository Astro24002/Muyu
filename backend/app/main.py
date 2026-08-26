from __future__ import annotations

import math
import os
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request, status
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text

from app.auth.routes import mobile_router
from app.auth.providers.fake import FakeSmsProvider
from app.auth.providers.production import ProductionSmsProvider
from app.core.config import get_settings
from app.db.migrations import run_migrations
from app.db.session import create_database_engine
from app.httpapi.errors import register_error_handlers
from app.devices.routes import compat_router as device_authorization_router
from app.devices.routes import router as devices_router
from app.recovery.routes import router as recovery_router
from app.realtime.hub import WorkspaceHub
from app.realtime.routes import router as realtime_router
from app.tasks.routes import router as tasks_router
from app.sync.routes import router as sync_router
from app.web_login.routes import router as web_login_router, sessions_router as web_sessions_router
from app.workspaces.routes import router as workspaces_router


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
            app.state.sms_provider = FakeSmsProvider(getattr(settings, "fake_otp_code", None))
        else:
            app.state.sms_provider = ProductionSmsProvider(
                str(settings.otp_provider_url),
                settings.otp_provider_api_key.get_secret_value(),
                sms_sign_id=settings.otp_sms_sign_id,
                template_id=settings.otp_sms_template_id,
                validity_minutes=max(1, math.ceil(settings.otp_ttl_seconds / 60)),
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
        allow_origins=_configured_cors_origins(),
        allow_origin_regex=r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$",
        allow_methods=["GET", "POST", "PATCH", "PUT", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type", "Idempotency-Key", "X-Request-ID"],
        allow_credentials=True,
    )
    app.state.ready = False
    app.state.sms_provider = None
    app.state.workspace_hub = WorkspaceHub()
    register_error_handlers(app)
    app.include_router(mobile_router)
    app.include_router(workspaces_router)
    app.include_router(devices_router)
    app.include_router(device_authorization_router)
    app.include_router(recovery_router)
    app.include_router(web_login_router)
    app.include_router(web_sessions_router)
    app.include_router(tasks_router)
    app.include_router(sync_router)
    app.include_router(realtime_router)

    @app.get("/health/live")
    def health_live() -> dict[str, str]:
        return {"status": "live"}

    @app.get("/health/ready")
    def health_ready(request: Request) -> dict[str, str]:
        if not app.state.ready:
            raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="service is starting")
        try:
            with request.app.state.engine.connect() as connection:
                connection.execute(text("SELECT 1"))
        except Exception as error:
            raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="database is unavailable") from error
        return {"status": "ready"}

    @app.get("/healthz", include_in_schema=False)
    def legacy_healthz(request: Request) -> dict[str, str]:
        health_ready(request)
        return {"status": "ok"}

    return app


def _configured_cors_origins() -> list[str]:
    """Return explicit deployment origins without enabling a wildcard."""

    values = [
        item.strip().rstrip("/")
        for raw in (os.environ.get("ALLOWED_ORIGINS", ""), os.environ.get("WEB_ORIGIN", ""))
        for item in raw.split(",")
        if item.strip()
    ]
    return list(dict.fromkeys(values))
