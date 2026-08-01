"""Occurrence expansion: the rules a calendar depends on — anchors that only
happen once, yearly anniversaries, and the Feb 29 observance."""

from datetime import date

from budgetbox.domain.events import occurrences_between


def test_non_repeating_event_only_shows_inside_the_window() -> None:
    anchor = date(2026, 8, 14)
    assert occurrences_between(anchor, False, date(2026, 8, 1), date(2026, 9, 1)) == [anchor]
    # Window ends the day it falls: end is exclusive.
    assert occurrences_between(anchor, False, date(2026, 8, 1), date(2026, 8, 14)) == []
    assert occurrences_between(anchor, False, date(2026, 8, 15), date(2026, 9, 1)) == []
    # Start is inclusive.
    assert occurrences_between(anchor, False, anchor, date(2026, 8, 15)) == [anchor]


def test_yearly_event_repeats_every_year_in_range() -> None:
    anchor = date(2020, 3, 9)
    assert occurrences_between(anchor, True, date(2026, 1, 1), date(2029, 1, 1)) == [
        date(2026, 3, 9),
        date(2027, 3, 9),
        date(2028, 3, 9),
    ]
    # A window that straddles a year boundary picks up exactly one anniversary.
    assert occurrences_between(anchor, True, date(2026, 12, 1), date(2027, 4, 1)) == [
        date(2027, 3, 9)
    ]


def test_feb_29_anchor_is_observed_on_feb_28_in_common_years() -> None:
    anchor = date(2024, 2, 29)  # leap
    assert occurrences_between(anchor, True, date(2025, 1, 1), date(2029, 1, 1)) == [
        date(2025, 2, 28),
        date(2026, 2, 28),
        date(2027, 2, 28),
        date(2028, 2, 29),  # leap again: back to the real day
    ]


def test_occurrences_never_precede_the_anchor_year() -> None:
    anchor = date(2026, 6, 1)
    assert occurrences_between(anchor, True, date(2020, 1, 1), date(2026, 1, 1)) == []
    assert occurrences_between(anchor, True, date(2024, 1, 1), date(2028, 1, 1)) == [
        date(2026, 6, 1),
        date(2027, 6, 1),
    ]
    # The anchor year itself counts, but not a date before the anchor within it.
    assert occurrences_between(anchor, True, date(2026, 1, 1), date(2026, 6, 1)) == []


def test_empty_or_inverted_window_yields_nothing() -> None:
    anchor = date(2026, 6, 1)
    assert occurrences_between(anchor, False, date(2026, 6, 1), date(2026, 6, 1)) == []
    assert occurrences_between(anchor, True, date(2026, 6, 1), date(2026, 6, 1)) == []
