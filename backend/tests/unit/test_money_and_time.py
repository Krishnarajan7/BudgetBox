from datetime import UTC, date, datetime, timedelta, timezone

import pytest

from budgetbox.core.money import format_inr
from budgetbox.core.time import day_key, ist_day_start


def test_format_inr_indian_grouping() -> None:
    assert format_inr(0) == "₹0.00"
    assert format_inr(123) == "₹1.23"
    assert format_inr(100_00) == "₹100.00"
    assert format_inr(1000_00) == "₹1,000.00"
    assert format_inr(12_34_567_89) == "₹12,34,567.89"
    assert format_inr(1_00_00_00_000_00) == "₹1,00,00,00,000.00"  # 100 crore
    assert format_inr(-4999) == "-₹49.99"


def test_day_key_is_ist_not_utc() -> None:
    # 18:35 UTC is already the next day in IST (+05:30).
    assert day_key(datetime(2026, 7, 31, 18, 35, tzinfo=UTC)) == date(2026, 8, 1)
    assert day_key(datetime(2026, 7, 31, 18, 25, tzinfo=UTC)) == date(2026, 7, 31)


def test_day_key_normalizes_other_zones() -> None:
    # 21:05 in +08:00 = 13:05 UTC = 18:35 IST, still July 31.
    tz = timezone(timedelta(hours=8))
    assert day_key(datetime(2026, 7, 31, 21, 5, tzinfo=tz)) == date(2026, 7, 31)


def test_day_key_rejects_naive() -> None:
    with pytest.raises(ValueError, match="naive"):
        day_key(datetime(2026, 7, 31, 12, 0))


def test_ist_day_start_roundtrips() -> None:
    start = ist_day_start(date(2026, 8, 1))
    assert day_key(start) == date(2026, 8, 1)
    assert day_key(start - timedelta(microseconds=1)) == date(2026, 7, 31)
