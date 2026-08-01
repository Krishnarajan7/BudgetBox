"""Read model behind the Today screen: spent-so-far hero, salary-month pace line,
pinned strip, today's entries, seal state. Upcoming recurrings join in Phase 3."""

from datetime import date, timedelta

from fastapi import APIRouter

from budgetbox.api.deps import SessionDep
from budgetbox.api.schemas import APIModel, StrictPaise
from budgetbox.core.time import ist_day_start, today_ist
from budgetbox.modules.recurring import service as recurring_service
from budgetbox.modules.recurring.schemas import DueItem
from budgetbox.modules.settings import service as settings_service
from budgetbox.modules.summary.window import salary_window_state
from budgetbox.modules.transactions import service as txn_service
from budgetbox.modules.transactions.schemas import PinnedOut, TxnOut

router = APIRouter(prefix="/summary", tags=["summary"])


class TodaySummary(APIModel):
    day: date
    sealed: bool
    spent_today_paise: StrictPaise
    window_start: date
    window_end: date
    window_spent_paise: StrictPaise
    window_elapsed_days: int
    window_total_days: int
    pinned: list[PinnedOut]
    today_txns: list[TxnOut]
    upcoming: list[DueItem]  # committed charges due in the next 7 days


@router.get("/today")
def today(session: SessionDep) -> TodaySummary:
    day = today_ist()
    window = salary_window_state(day, settings_service.salary_day(session))

    spent_today = txn_service.spent_between(
        session, ist_day_start(day), ist_day_start(window.tomorrow)
    )
    window_spent = txn_service.spent_between(
        session, ist_day_start(window.start), ist_day_start(window.end)
    )
    today_rows, _ = txn_service.list_txns(session, from_day=day, to_day=window.tomorrow, limit=500)
    return TodaySummary(
        day=day,
        sealed=txn_service.is_sealed(session, day),
        spent_today_paise=spent_today,
        window_start=window.start,
        window_end=window.end,
        window_spent_paise=window_spent,
        window_elapsed_days=window.elapsed_days,
        window_total_days=window.total_days,
        pinned=[PinnedOut.model_validate(p) for p in txn_service.list_pinned(session)],
        today_txns=[TxnOut.model_validate(t) for t in today_rows],
        upcoming=recurring_service.upcoming(session, until=day + timedelta(days=7)),
    )
