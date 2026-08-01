"""RFC 9457 problem+json error responses. Every DomainError maps to a stable
`type` URN the Dart client can switch on; nothing else leaks out of handlers."""

from typing import Any

import structlog
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from budgetbox.core.errors import DomainError

log = structlog.get_logger()

PROBLEM_CONTENT_TYPE = "application/problem+json"


def problem(
    *,
    status: int,
    slug: str,
    title: str,
    detail: str,
    errors: list[dict[str, Any]] | None = None,
    headers: dict[str, str] | None = None,
) -> JSONResponse:
    body: dict[str, Any] = {
        "type": f"urn:budgetbox:problem:{slug}",
        "title": title,
        "status": status,
        "detail": detail,
    }
    if errors is not None:
        body["errors"] = errors
    return JSONResponse(body, status_code=status, media_type=PROBLEM_CONTENT_TYPE, headers=headers)


def register_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(DomainError)
    async def _domain_error(_request: Request, exc: DomainError) -> JSONResponse:
        headers = {"WWW-Authenticate": "Bearer"} if exc.status == 401 else None
        return problem(
            status=exc.status, slug=exc.slug, title=exc.title, detail=exc.detail, headers=headers
        )

    @app.exception_handler(RequestValidationError)
    async def _validation_error(_request: Request, exc: RequestValidationError) -> JSONResponse:
        errors = [
            {"loc": [str(part) for part in err["loc"]], "msg": err["msg"], "type": err["type"]}
            for err in exc.errors()
        ]
        return problem(
            status=422,
            slug="validation-error",
            title="Validation failed",
            detail="One or more fields are invalid.",
            errors=errors,
        )

    @app.exception_handler(Exception)
    async def _unhandled(_request: Request, exc: Exception) -> JSONResponse:
        log.exception("unhandled_error", error=type(exc).__name__)
        return problem(
            status=500,
            slug="internal",
            title="Internal error",
            detail="Something broke on the server; the details are in its logs.",
        )
