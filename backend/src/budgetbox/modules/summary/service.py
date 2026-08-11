"""Screen-shaped read models. The phone is on a train half the time, so a screen
gets its whole month in one call rather than a dozen chatty ones."""

import datetime as dt

from sqlalchemy import select
from sqlalchemy.orm import Session

from budgetbox.core.time import day_key, ist_day_start
from budgetbox.domain.periods import month_end_exclusive, month_start
from budgetbox.domain.recurrence import occurrences_in_window
from budgetbox.modules.events import service as event_service
from budgetbox.modules.recurring import service as recurring_service
from budgetbox.modules.recurring.models import Recurring, RecurringKind
from budgetbox.modules.recurring.schemas import DueItem, RecurringOut
from budgetbox.modules.summary.schemas import (
    CalendarWindow,
    CategorySlice,
    DayMoney,
    DayTotal,
    MonthSummary,
)
from budgetbox.modules.transactions import service as txn_service
from budgetbox.modules.transactions.models import Txn, TxnType
from budgetbox.modules.transactions.schemas import TxnOut


def month_summary(session: Session, *, month: dt.date, today: dt.date) -> MonthSummary:
    """Everything the Book draws for one month: the in/out/kept line, the heat grid,
    where it went, and the entry that carried the most weight."""
    start = month_start(month)
    end = month_end_exclusive(month)
    rows = list(
        session.scalars(
            select(Txn)
            .where(Txn.at >= ist_day_start(start), Txn.at < ist_day_start(end))
            .order_by(Txn.at.desc(), Txn.id.desc())
        )
    )

    total_days = (end - start).days
    spent = [0] * total_days
    earned = [0] * total_days
    entries = [0] * total_days
    in_paise = 0
    out_paise = 0
    by_category: dict[str | None, int] = {}
    biggest: Txn | None = None

    for row in rows:
        index = (day_key(row.at) - start).days
        entries[index] += 1
        if row.type is TxnType.EXPENSE:
            out_paise += row.amount_paise
            spent[index] += row.amount_paise
            by_category[row.category_id] = by_category.get(row.category_id, 0) + row.amount_paise
            if biggest is None or row.amount_paise > biggest.amount_paise:
                biggest = row
        elif row.type is TxnType.INCOME:
            in_paise += row.amount_paise
            earned[index] += row.amount_paise

    # Days lived, not days on the calendar: a month still running is judged only
    # as far as it has been written.
    elapsed = total_days if today >= end else max((today - start).days + 1, 0)
    quiet = sum(1 for i in range(elapsed) if spent[i] == 0)

    heaviest_day: dt.date | None = None
    heaviest = 0
    for i in range(total_days):
        if spent[i] > heaviest:  # ties go to the earlier day
            heaviest, heaviest_day = spent[i], start + dt.timedelta(days=i)

    share = (biggest.amount_paise / out_paise) if biggest is not None and out_paise > 0 else None

    return MonthSummary(
        month=f"{start.year:04d}-{start.month:02d}",
        start=start,
        end=end,
        in_paise=in_paise,
        out_paise=out_paise,
        kept_paise=in_paise - out_paise,
        entry_count=len(rows),
        elapsed_days=elapsed,
        total_days=total_days,
        quiet_days=quiet,
        heaviest_day=heaviest_day,
        heaviest_day_paise=heaviest,
        day_totals=[
            DayTotal(
                date=start + dt.timedelta(days=i),
                spent_paise=spent[i],
                earned_paise=earned[i],
                entry_count=entries[i],
            )
            for i in range(total_days)
        ],
        categories=sorted(
            (
                CategorySlice(category_id=cid, spent_paise=paise)
                for cid, paise in by_category.items()
            ),
            key=lambda s: (-s.spent_paise, s.category_id or ""),
        ),
        biggest_expense=TxnOut.model_validate(biggest) if biggest is not None else None,
        biggest_expense_share=share,
        sealed_days=[s.date for s in txn_service.seals_between(session, start, end)],
        salary_day_of_month=txn_service.largest_income_day(session, start, end),
    )


def calendar_window(session: Session, *, from_day: dt.date, to_day: dt.date) -> CalendarWindow:
    """The calendar's money layer over [from_day, to_day): what was spent each day,
    what is committed to land, and what he wrote down to remember."""
    charges: list[DueItem] = []
    for row in session.scalars(select(Recurring).where(Recurring.active.is_(True))):
        out = RecurringOut.model_validate(row)
        for due in occurrences_in_window(
            row.next_due, row.every_months, row.day_of_month, from_day, to_day
        ):
            charges.append(DueItem(recurring=out, due=due, is_bill=row.kind is RecurringKind.BILL))
    charges.sort(key=lambda c: (c.due, c.recurring.title))

    money = txn_service.money_by_day(session, from_day, to_day)
    return CalendarWindow(
        from_day=from_day,
        to_day=to_day,
        days=[
            DayMoney(date=day, spent_paise=spent, earned_paise=earned)
            for day, (spent, earned) in sorted(money.items())
        ],
        charges=charges,
        charge_total_paise=sum(c.recurring.amount_paise for c in charges),
        events=event_service.occurrences(session, from_day, to_day),
    )


def committed_this_month(session: Session, *, today: dt.date) -> int:
    """What the rest of this month has already been promised away — the honest
    number behind 'left to spend'. Charges already posted don't count twice."""
    return recurring_service.committed_due_between(session, today, month_end_exclusive(today))
