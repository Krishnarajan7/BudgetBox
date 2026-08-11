from datetime import date

from budgetbox.api.schemas import APIModel, StrictPaise
from budgetbox.modules.events.schemas import OccurrenceOut
from budgetbox.modules.recurring.schemas import DueItem
from budgetbox.modules.transactions.schemas import PinnedOut, TxnOut


class DayTotal(APIModel):
    date: date
    spent_paise: StrictPaise
    earned_paise: StrictPaise
    entry_count: int


class CategorySlice(APIModel):
    """Where it went. A null category is the uncategorised pile, not a total."""

    category_id: str | None
    spent_paise: StrictPaise


class MonthSummary(APIModel):
    month: str  # 'yyyy-MM'
    start: date
    end: date  # exclusive
    in_paise: StrictPaise
    out_paise: StrictPaise
    kept_paise: StrictPaise
    entry_count: int  # every type, transfers included
    elapsed_days: int
    total_days: int
    quiet_days: int  # elapsed days with nothing spent
    heaviest_day: date | None
    heaviest_day_paise: StrictPaise
    day_totals: list[DayTotal]  # one per calendar day, oldest first
    categories: list[CategorySlice]  # heaviest first
    biggest_expense: TxnOut | None
    biggest_expense_share: float | None  # of the month's spend
    sealed_days: list[date]
    salary_day_of_month: int | None  # where the biggest paycheque landed


class DayMoney(APIModel):
    date: date
    spent_paise: StrictPaise
    earned_paise: StrictPaise


class CalendarWindow(APIModel):
    from_day: date
    to_day: date  # exclusive
    days: list[DayMoney]  # only days that saw money move
    charges: list[DueItem]  # committed charges landing in the window
    charge_total_paise: StrictPaise
    events: list[OccurrenceOut]


class TodaySummary(APIModel):
    day: date
    sealed: bool
    seal_streak_days: int
    spent_today_paise: StrictPaise
    spent_yesterday_paise: StrictPaise
    window_start: date
    window_end: date
    window_spent_paise: StrictPaise
    window_elapsed_days: int
    window_total_days: int
    committed_paise: StrictPaise  # unposted charges still due this month
    quiet_days: list[date]  # the last week's blank days, most recent first
    pinned: list[PinnedOut]
    today_txns: list[TxnOut]
    upcoming: list[DueItem]  # committed charges due in the next 7 days
