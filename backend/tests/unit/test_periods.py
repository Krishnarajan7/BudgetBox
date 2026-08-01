from datetime import date

from budgetbox.domain.periods import (
    add_months,
    clamp_day,
    days_in_month,
    fy_end_exclusive,
    fy_label,
    fy_start,
    month_end_exclusive,
    month_start,
    salary_month_window,
)


def test_add_months_wraps_years() -> None:
    assert add_months(2026, 12, 1) == (2027, 1)
    assert add_months(2026, 1, -1) == (2025, 12)
    assert add_months(2026, 7, 12) == (2027, 7)
    assert add_months(2026, 7, 0) == (2026, 7)


def test_clamp_day() -> None:
    assert clamp_day(2026, 2, 31) == date(2026, 2, 28)
    assert clamp_day(2028, 2, 31) == date(2028, 2, 29)  # leap
    assert clamp_day(2026, 4, 31) == date(2026, 4, 30)
    assert clamp_day(2026, 1, 31) == date(2026, 1, 31)


def test_month_window() -> None:
    assert month_start(date(2026, 7, 31)) == date(2026, 7, 1)
    assert month_end_exclusive(date(2026, 7, 31)) == date(2026, 8, 1)
    assert month_end_exclusive(date(2026, 12, 5)) == date(2027, 1, 1)
    assert days_in_month(date(2026, 2, 1)) == 28
    assert days_in_month(date(2028, 2, 1)) == 29


def test_fy_boundaries() -> None:
    # Exact cases documented in lib/core/dates.dart.
    assert fy_start(date(2026, 7, 31)) == date(2026, 4, 1)
    assert fy_start(date(2026, 2, 10)) == date(2025, 4, 1)
    assert fy_start(date(2026, 3, 31)) == date(2025, 4, 1)
    assert fy_start(date(2026, 4, 1)) == date(2026, 4, 1)
    assert fy_end_exclusive(date(2026, 7, 31)) == date(2027, 4, 1)


def test_fy_label() -> None:
    assert fy_label(date(2026, 7, 31)) == "FY 26-27"
    assert fy_label(date(2026, 2, 10)) == "FY 25-26"
    assert fy_label(date(2099, 12, 1)) == "FY 99-00"


def test_salary_month_is_calendar_month_for_day_1() -> None:
    assert salary_month_window(date(2026, 7, 15), 1) == (date(2026, 7, 1), date(2026, 8, 1))
    assert salary_month_window(date(2026, 7, 1), 1) == (date(2026, 7, 1), date(2026, 8, 1))


def test_salary_month_mid_month_anchor() -> None:
    # Salary on the 25th: July 10 is still inside the June-25 month.
    assert salary_month_window(date(2026, 7, 10), 25) == (date(2026, 6, 25), date(2026, 7, 25))
    assert salary_month_window(date(2026, 7, 25), 25) == (date(2026, 7, 25), date(2026, 8, 25))


def test_salary_day_31_clamps_in_february() -> None:
    # Before Feb's clamped anchor: window is Jan 31 → Feb 28.
    assert salary_month_window(date(2026, 2, 15), 31) == (date(2026, 1, 31), date(2026, 2, 28))
    # On/after the clamped anchor: Feb 28 → Mar 31.
    assert salary_month_window(date(2026, 2, 28), 31) == (date(2026, 2, 28), date(2026, 3, 31))
