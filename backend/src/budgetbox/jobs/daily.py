"""The daily catch-up: materialize due recurrings (and, from Phase 5, snapshot
balances). Invoked by the systemd timer at 00:05 IST, by `budgetbox jobs daily`,
and once before serve starts — reruns are always safe."""

from sqlalchemy.orm import Session, sessionmaker

from budgetbox.jobs.runner import run_jobs
from budgetbox.modules.coaching import service as coaching_service
from budgetbox.modules.folio import service as folio_service
from budgetbox.modules.networth import service as networth_service
from budgetbox.modules.recurring import service as recurring_service

DAILY = "daily"


def materialize_recurrings(session: Session) -> str:
    created = recurring_service.materialize_due(session)
    return f"materialized {created} txn(s)"


def snapshot_balances(session: Session) -> str:
    """After materialization, so today's posted bills land in today's snapshot."""
    written = networth_service.snapshot_all(session)
    return f"wrote {written} snapshot(s)"


def generate_coaching(session: Session) -> str:
    created = coaching_service.generate(session)
    return f"created {created} coaching insight(s)"


def price_funds(session: Session) -> str:
    """AMFI first, then the anchor — the snapshot below reads the anchor, so a
    fund that moved today lands in today's net worth rather than tomorrow's.
    A market holiday or an unreachable AMFI is not a failure: yesterday's NAV
    is still the truest number available."""
    from budgetbox.modules.folio import amfi

    try:
        priced = folio_service.refresh_navs(session)
    except amfi.AmfiError as exc:
        return f"navs unavailable ({exc.detail[:60]})"
    return f"priced {priced} fund(s); {folio_service.anchor_worth(session)}"


def run_daily(factory: sessionmaker[Session]) -> bool:
    return run_jobs(
        factory,
        DAILY,
        [materialize_recurrings, price_funds, snapshot_balances, generate_coaching],
    )
