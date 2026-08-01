"""Recurring schedule math. A recurring keeps its intended day_of_month even after
clamping (rent on the 31st bills Feb 28, then Mar 31 again), which is why the day
travels separately from the last due date."""

from datetime import date

from budgetbox.domain.periods import add_months, clamp_day


def advance(due: date, every_months: int, day_of_month: int) -> date:
    """The due date after `due`."""
    year, month = add_months(due.year, due.month, every_months)
    return clamp_day(year, month, day_of_month)


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
