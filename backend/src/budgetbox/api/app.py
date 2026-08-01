import time as _time
from collections.abc import Awaitable, Callable

import structlog
from fastapi import APIRouter, Depends, FastAPI, Request, Response
from sqlalchemy import text

from budgetbox.api.auth import require_device
from budgetbox.api.problems import register_error_handlers
from budgetbox.core.config import Settings, settings
from budgetbox.core.ids import new_id
from budgetbox.core.logging import configure_logging
from budgetbox.db.engine import make_engine
from budgetbox.db.session import make_session_factory
from budgetbox.modules.registry import all_routers, import_all_models

log = structlog.get_logger()


def create_app(cfg: Settings | None = None) -> FastAPI:
    cfg = cfg or settings()
    configure_logging(env=cfg.env, level=cfg.log_level)
    import_all_models()

    app = FastAPI(
        title="BudgetBox",
        version="1.0",
        docs_url="/docs" if cfg.env == "dev" else None,
        redoc_url=None,
    )
    app.state.settings = cfg
    engine = make_engine(cfg.db_path)
    app.state.engine = engine
    app.state.session_factory = make_session_factory(engine)

    register_error_handlers(app)

    @app.middleware("http")
    async def _request_log(
        request: Request, call_next: Callable[[Request], Awaitable[Response]]
    ) -> Response:
        structlog.contextvars.bind_contextvars(request_id=new_id())
        started = _time.perf_counter()
        try:
            response = await call_next(request)
        finally:
            structlog.contextvars.unbind_contextvars("request_id")
        log.info(
            "request",
            method=request.method,
            path=request.url.path,
            status=response.status_code,
            duration_ms=round((_time.perf_counter() - started) * 1000, 1),
        )
        return response

    @app.get("/healthz", include_in_schema=False)
    def healthz() -> dict[str, str | bool | None]:
        from budgetbox.jobs.daily import DAILY
        from budgetbox.jobs.runner import last_run

        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        daily_ok: bool | None = None
        daily_at: str | None = None
        try:
            with app.state.session_factory() as session:
                run = last_run(session, DAILY)
                if run is not None:
                    daily_ok = run.ok
                    daily_at = run.started_at.isoformat()
        except Exception:  # pre-migration DB: still "up", just unprovisioned
            pass
        return {"status": "ok", "daily_job_ok": daily_ok, "daily_job_at": daily_at}

    v1 = APIRouter(prefix="/v1", dependencies=[Depends(require_device)])

    @v1.get("/ping")
    def ping() -> dict[str, bool]:
        """Connectivity + auth probe for the app."""
        return {"ok": True}

    for router in all_routers():
        v1.include_router(router)
    app.include_router(v1)

    return app
