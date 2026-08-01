import datetime as dt
import re

from budgetbox.core.errors import Invalid

_MONTH_RE = re.compile(r"^(\d{4})-(\d{2})$")


def parse_month(month: str | None) -> dt.date | None:
    """'2026-07' -> date(2026, 7, 1); None passes through; anything else is a 422."""
    if month is None:
        return None
    m = _MONTH_RE.match(month)
    if m is None or not 1 <= int(m.group(2)) <= 12:
        raise Invalid("month must look like 2026-07")
    return dt.date(int(m.group(1)), int(m.group(2)), 1)
