"""Time rules. Two kinds of time exist and never mix implicitly:

- *Instants* are tz-aware datetimes, stored as UTC ISO-8601 text.
- *Calendar days* are `datetime.date`, stored as 'yyyy-MM-dd' text, and always mean
  a day in IST — an entry made at 00:30 IST belongs to that IST day no matter where
  the server runs.

`day_key` is the single chokepoint where an instant becomes a day.
"""

from datetime import UTC, date, datetime
from zoneinfo import ZoneInfo

IST = ZoneInfo("Asia/Kolkata")


def now_utc() -> datetime:
    return datetime.now(UTC)


def day_key(instant: datetime) -> date:
    """The only way an instant becomes a calendar day: convert to IST, take the date."""
    if instant.tzinfo is None:
        raise ValueError("naive datetime reached day_key; instants must be tz-aware")
    return instant.astimezone(IST).date()


def today_ist() -> date:
    return day_key(now_utc())


def ist_day_start(day: date) -> datetime:
    """The instant an IST calendar day begins, as a tz-aware datetime."""
    return datetime(day.year, day.month, day.day, tzinfo=IST)
