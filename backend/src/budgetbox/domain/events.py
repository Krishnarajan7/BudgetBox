"""Occurrence expansion for calendar events — the logic layer the Events table
never had. Pure; takes anchors, returns concrete dates."""

import datetime as dt

from budgetbox.domain.periods import clamp_day


def occurrences_between(
    anchor: dt.date, repeat_yearly: bool, start: dt.date, end_exclusive: dt.date
) -> list[dt.date]:
    """Concrete dates for one event inside [start, end). Non-repeating: the anchor
    if it falls in range. Yearly: the anniversary each year, with a Feb 29 anchor
    observed on Feb 28 in common years."""
    if not repeat_yearly:
        return [anchor] if start <= anchor < end_exclusive else []
    out: list[dt.date] = []
    for year in range(start.year, end_exclusive.year + 1):
        if year < anchor.year:
            continue
        occurrence = clamp_day(year, anchor.month, anchor.day)
        if start <= occurrence < end_exclusive:
            out.append(occurrence)
    return out
