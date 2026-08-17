from __future__ import annotations

from uuid import uuid4

from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.middleware.base import RequestResponseEndpoint
from starlette.responses import Response


class ApiError(Exception):
    def __init__(self, status_code: int, code: str, message: str, details: object | None = None) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.code = code
        self.message = message
        self.details = {} if details is None else details


def register_error_handlers(app: FastAPI) -> None:
    @app.middleware("http")
    async def request_id_middleware(request: Request, call_next: RequestResponseEndpoint) -> Response:
        request_id = request.headers.get("X-Request-ID") or str(uuid4())
        request.state.request_id = request_id
        response = await call_next(request)
        response.headers["X-Request-ID"] = request_id
        return response

    @app.exception_handler(ApiError)
    async def api_error_handler(request: Request, error: ApiError) -> JSONResponse:
        return _json_error(request, error.status_code, error.code, error.message, error.details)

    @app.exception_handler(RequestValidationError)
    async def validation_error_handler(request: Request, error: RequestValidationError) -> JSONResponse:
        details = [{"loc": list(item["loc"]), "msg": item["msg"]} for item in error.errors()]
        return _json_error(request, 422, "VALIDATION_ERROR", "request validation failed", details)

    @app.exception_handler(HTTPException)
    async def http_error_handler(request: Request, error: HTTPException) -> JSONResponse:
        code = {
            400: "BAD_REQUEST",
            401: "UNAUTHORIZED",
            404: "NOT_FOUND",
            429: "RATE_LIMITED",
        }.get(error.status_code, "HTTP_ERROR")
        return _json_error(request, error.status_code, code, str(error.detail), {})

    @app.exception_handler(Exception)
    async def internal_error_handler(request: Request, _error: Exception) -> JSONResponse:
        return _json_error(request, 500, "INTERNAL_ERROR", "internal server error", {})


def _json_error(request: Request, status_code: int, code: str, message: str, details: object) -> JSONResponse:
    response = JSONResponse(
        status_code=status_code,
        content={"code": code, "message": message, "details": details},
    )
    request_id = getattr(request.state, "request_id", None)
    if request_id is not None:
        response.headers["X-Request-ID"] = request_id
    return response
