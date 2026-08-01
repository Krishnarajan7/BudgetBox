"""Calendar arithmetic: months, the Indian financial year (April-March), and the
salary-anchored month. Pure functions over datetime.date — no tz, no DB, no I/O.

Port of lib/core/dates.dart; semantics must not drift from the app."""

import calendar
from datetime import date


def add_months(year: int, month: int, delta: int) -> tuple[int, int]:
    index = year * 12 + (month - 1) + delta
    return index // 12, index % 12 + 1


def clamp_day(year: int, month: int, day: int) -> date:
    """The given day-of-month, clamped to the month's length (31 → Feb 28/29)."""
    return date(year, month, min(day, calendar.monthrange(year, month)[1]))


def month_start(d: date) -> date:
    return d.replace(day=1)


def month_end_exclusive(d: date) -> date:
    year, month = add_months(d.year, d.month, 1)
    return date(year, month, 1)


def days_in_month(d: date) -> int:
    return calendar.monthrange(d.year, d.month)[1]


def fy_start(d: date) -> date:
    """Indian financial year: April-March. fy_start(2026-07-31) = 2026-04-01;
    fy_start(2026-02-10) = 2025-04-01."""
    return date(d.year if d.month >= 4 else d.year - 1, 4, 1)


def fy_end_exclusive(d: date) -> date:
    return date(fy_start(d).year + 1, 4, 1)


def fy_label(d: date) -> str:
    """'FY 26-27' for the financial year containing d."""
    start_year = fy_start(d).year
    return f"FY {start_year % 100:02d}-{(start_year + 1) % 100:02d}"


def salary_month_window(today: date, salary_day: int) -> tuple[date, date]:
    """[start, end) of the salary-anchored month containing `today`: it runs from
    the salary day (clamped to month length) to the next one. salary_day=1 is the
    calendar month."""
    anchor = clamp_day(today.year, today.month, salary_day)
    if today >= anchor:
        start = anchor
    else:
        year, month = add_months(today.year, today.month, -1)
        start = clamp_day(year, month, salary_day)
    year, month = add_months(start.year, start.month, 1)
    return start, clamp_day(year, month, salary_day)
