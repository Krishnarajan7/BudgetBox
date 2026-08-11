"""Screen-shaped read models: Today's hero and shelf, the Book's whole month, and
the calendar's money layer. Each is one call, because the phone may be on a train."""

from datetime import date, timedelta

from fastapi import APIRouter

from budgetbox.api.deps import SessionDep
from budgetbox.api.params import parse_month
from budgetbox.core.time import ist_day_start, today_ist
from budgetbox.modules.recurring import service as recurring_service
from budgetbox.modules.settings import service as settings_service
from budgetbox.modules.summary import service
from budgetbox.modules.summary.schemas import CalendarWindow, MonthSummary, TodaySummary
from budgetbox.modules.summary.window import salary_window_state
from budgetbox.modules.transactions import service as txn_service
from budgetbox.modules.transactions.schemas import PinnedOut, TxnOut

router = APIRouter(prefix="/summary", tags=["summary"])


@router.get("/today")
def today(session: SessionDep) -> TodaySummary:
    day = today_ist()
    yesterday = day - timedelta(days=1)
    window = salary_window_state(day, settings_service.salary_day(session))

    spent_today = txn_service.spent_between(
        session, ist_day_start(day), ist_day_start(window.tomorrow)
    )
    spent_yesterday = txn_service.spent_between(
        session, ist_day_start(yesterday), ist_day_start(day)
    )
    window_spent = txn_service.spent_between(
        session, ist_day_start(window.start), ist_day_start(window.end)
    )
    today_rows, _ = txn_service.list_txns(session, from_day=day, to_day=window.tomorrow, limit=500)
    return TodaySummary(
        day=day,
        sealed=txn_service.is_sealed(session, day),
        seal_streak_days=txn_service.seal_streak_days(session, day),
        spent_today_paise=spent_today,
        spent_yesterday_paise=spent_yesterday,
        window_start=window.start,
        window_end=window.end,
        window_spent_paise=window_spent,
        window_elapsed_days=window.elapsed_days,
        window_total_days=window.total_days,
        committed_paise=service.committed_this_month(session, today=day),
        quiet_days=txn_service.quiet_days(session, today=day),
        pinned=[PinnedOut.model_validate(p) for p in txn_service.list_pinned(session)],
        today_txns=[TxnOut.model_validate(t) for t in today_rows],
        upcoming=recurring_service.upcoming(session, until=day + timedelta(days=7)),
    )


@router.get("/month")
def month(session: SessionDep, month: str | None = None) -> MonthSummary:
    """The Book's month: in/out/kept, the heat grid, where it went, and the entry
    that carried the most weight."""
    today = today_ist()
    return service.month_summary(session, month=parse_month(month) or today, today=today)


@router.get("/calendar")
def calendar(session: SessionDep, from_day: date, to_day: date) -> CalendarWindow:
    """The calendar's money layer over [from_day, to_day): per-day spend, committed
    charges laid over the grid, and event occurrences."""
    return service.calendar_window(session, from_day=from_day, to_day=to_day)
