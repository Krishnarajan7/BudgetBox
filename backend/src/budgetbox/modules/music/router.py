from typing import Annotated

from fastapi import APIRouter, Query, Request
from fastapi.responses import HTMLResponse

from budgetbox.api.deps import SessionDep
from budgetbox.api.params import parse_month
from budgetbox.core.config import Settings
from budgetbox.core.errors import DomainError, Invalid
from budgetbox.modules.music import service
from budgetbox.modules.music.schemas import (
    ConnectOut,
    MonthDetailOut,
    MonthOut,
    NowOut,
    OverviewOut,
    TopEntryOut,
)

router = APIRouter(prefix="/music", tags=["music"])


@router.get("/overview")
def overview(session: SessionDep) -> OverviewOut:
    return service.overview(session)


@router.get("/top")
def top(
    session: SessionDep,
    kind: str = "tracks",
    range: str = "all",
    limit: Annotated[int, Query(ge=1, le=50)] = 10,
) -> list[TopEntryOut]:
    return service.top(session, kind=kind, range_key=range, limit=limit)


@router.get("/months")
def months(session: SessionDep) -> list[MonthOut]:
    return service.months(session)


@router.get("/months/{month}")
def month_detail(session: SessionDep, month: str) -> MonthDetailOut:
    parsed = parse_month(month)
    if parsed is None:  # pragma: no cover — path params are never None
        raise Invalid("month must look like 2026-07")
    return service.month_detail(session, parsed)


@router.get("/now")
def now(session: SessionDep, request: Request) -> NowOut:
    return service.now(session, _settings(request))


@router.post("/spotify/connect")
def connect(session: SessionDep, request: Request) -> ConnectOut:
    return service.connect_begin(session, _settings(request))


def _settings(request: Request) -> Settings:
    cfg: Settings = request.app.state.settings
    return cfg


# ————— the public callback —————
#
# Spotify's consent page redirects a plain browser here; a browser cannot
# carry the device token, so this router mounts outside /v1. Its protection
# is the PKCE state: a callback with the wrong or stale state spends nothing.

public_router = APIRouter()


@public_router.get("/spotify/callback", include_in_schema=False)
def spotify_callback(
    session: SessionDep,
    request: Request,
    code: str | None = None,
    state: str | None = None,
    error: str | None = None,
) -> HTMLResponse:
    if error is not None:
        return _page(f"Spotify said: {error}. Nothing was connected.", ok=False)
    if not code or not state:
        return _page("Missing code or state — start the connection again.", ok=False)
    try:
        service.connect_finish(session, _settings(request), code, state)
    except DomainError as exc:
        return _page(exc.detail, ok=False)
    return _page("Spotify is connected. You can close this tab — the book takes it from here.")


def _page(message: str, ok: bool = True) -> HTMLResponse:
    tone = "#1a7f4e" if ok else "#b3392b"
    return HTMLResponse(
        "<!doctype html><meta charset='utf-8'>"
        "<title>BudgetBox</title>"
        "<body style='font-family:system-ui;background:#111;color:#eee;"
        "display:grid;place-items:center;height:100vh;margin:0'>"
        f"<div style='max-width:26rem;padding:2rem;text-align:center'>"
        f"<h1 style='font-size:1.1rem;color:{tone}'>BudgetBox</h1>"
        f"<p>{message}</p></div>",
        status_code=200 if ok else 400,
    )
