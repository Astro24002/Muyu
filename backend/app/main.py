from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, status


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    app.state.ready = True
    yield
    app.state.ready = False


def create_app() -> FastAPI:
    app = FastAPI(title="Muyu API", lifespan=lifespan)

    @app.get("/healthz")
    def healthz() -> dict[str, str]:
        if not app.state.ready:
            raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="not ready")
        return {"status": "ok"}

    return app
