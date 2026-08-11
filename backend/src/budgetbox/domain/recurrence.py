"""Recurring schedule math. A recurring keeps its intended day_of_month even after
clamping (rent on the 31st bills Feb 28, then Mar 31 again), which is why the day
travels separately from the last due date."""

from datetime import date

from budgetbox.domain.periods import add_months, clamp_day


def advance(due: date, every_months: int, day_of_month: int) -> date:
    """The due date after `due`."""
    year, month = add_months(due.year, due.month, every_months)
    return clamp_day(year, month, day_of_month)


def retreat(due: date, every_months: int, day_of_month: int) -> date:
    """The due date before `due` — the same rhythm walked backwards, so a window in
    the past resolves the schedule the charge actually keeps."""
    year, month = add_months(due.year, due.month, -every_months)
    return clamp_day(year, month, day_of_month)


# A charge repeats at least every 60 months, so this bounds the walk at ~500 years.
_WALK_LIMIT = 6000


def occurrences_in_window(
    next_due: date, every_months: int, day_of_month: int, start: date, end_exclusive: date
) -> list[date]:
    """Every occurrence inside [start, end), phase-anchored on `next_due`. The
    calendar draws past months too, so this walks back before it walks forward."""
    due = next_due
    steps = 0
    while due > start and steps < _WALK_LIMIT:
        due = retreat(due, every_months, day_of_month)
        steps += 1
    out: list[date] = []
    while due < end_exclusive and steps < _WALK_LIMIT:
        if due >= start:
            out.append(due)
        due = advance(due, every_months, day_of_month)
        steps += 1
    return out


def occurrences_through(
    next_due: date, every_months: int, day_of_month: int, until: date
) -> list[date]:
    """Every due date from next_due through `until` inclusive — the catch-up list a
    materialization run must post. Empty when next_due is still in the future."""
    out: list[date] = []
    due = next_due
    while due <= until:
        out.append(due)
        due = advance(due, every_months, day_of_month)
    return out
