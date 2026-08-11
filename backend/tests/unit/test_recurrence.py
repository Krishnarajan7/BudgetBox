from datetime import date

from budgetbox.domain.recurrence import advance, occurrences_in_window, occurrences_through


def test_day_31_clamps_and_recovers() -> None:
    # Rent on the 31st: Jan 31 → Feb 28 → back to Mar 31.
    assert advance(date(2026, 1, 31), 1, 31) == date(2026, 2, 28)
    assert advance(date(2026, 2, 28), 1, 31) == date(2026, 3, 31)


def test_yearly_on_leap_day() -> None:
    assert advance(date(2028, 2, 29), 12, 29) == date(2029, 2, 28)
    assert advance(date(2029, 2, 28), 12, 29) == date(2030, 2, 28)
    # ...and lands back on the 29th when the year allows.
    assert advance(date(2031, 2, 28), 12, 29) == date(2032, 2, 29)


def test_quarterly() -> None:
    assert advance(date(2026, 1, 31), 3, 31) == date(2026, 4, 30)


def test_occurrences_catch_up_after_downtime() -> None:
    # Server was down since April; catching up to July 15 posts Apr/May/Jun/Jul.
    dues = occurrences_through(date(2026, 4, 5), 1, 5, date(2026, 7, 15))
    assert dues == [date(2026, 4, 5), date(2026, 5, 5), date(2026, 6, 5), date(2026, 7, 5)]


def test_occurrences_empty_when_next_due_in_future() -> None:
    assert occurrences_through(date(2026, 8, 1), 1, 1, date(2026, 7, 15)) == []


def test_occurrences_clamped_run() -> None:
    dues = occurrences_through(date(2026, 1, 31), 1, 31, date(2026, 4, 30))
    assert dues == [
        date(2026, 1, 31),
        date(2026, 2, 28),
        date(2026, 3, 31),
        date(2026, 4, 30),
    ]


def test_occurrences_in_window_walks_backwards_from_next_due() -> None:
    # A monthly charge whose next due is in August still shows in June's calendar.
    got = occurrences_in_window(date(2026, 8, 5), 1, 5, date(2026, 6, 1), date(2026, 8, 1))
    assert got == [date(2026, 6, 5), date(2026, 7, 5)]


def test_occurrences_in_window_keeps_the_cadence_phase() -> None:
    # A yearly plan renewing 2027-03-10: only its own anniversary lands, not
    # every March-ish month in between.
    got = occurrences_in_window(date(2027, 3, 10), 12, 10, date(2024, 1, 1), date(2028, 1, 1))
    assert got == [date(2024, 3, 10), date(2025, 3, 10), date(2026, 3, 10), date(2027, 3, 10)]


def test_occurrences_in_window_is_half_open_and_clamps_the_day() -> None:
    # Rent on the 31st bills Feb 28 without losing its intended day.
    got = occurrences_in_window(date(2026, 3, 31), 1, 31, date(2026, 1, 31), date(2026, 3, 31))
    assert got == [date(2026, 1, 31), date(2026, 2, 28)]  # end is exclusive
    assert occurrences_in_window(date(2026, 3, 31), 1, 31, date(2026, 4, 1), date(2026, 4, 1)) == []
