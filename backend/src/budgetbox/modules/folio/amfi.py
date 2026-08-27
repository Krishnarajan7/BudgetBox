"""AMFI's daily NAV file — the whole Indian mutual fund market, free, no key.

`NAVAll.txt` is a semicolon-delimited dump of every open-ended scheme, about
eighteen thousand rows, republished each working evening. It is the reason a
fund's worth in this book updates itself instead of being typed in from a
statement.

Nothing here touches the database: the service decides what to keep."""

from dataclasses import dataclass
from datetime import date, datetime

import httpx
import structlog

log = structlog.get_logger()

# amfiindia.com 302s here; going straight to the portal saves a redirect on
# every run and one class of "why did the job fail" mystery.
NAV_URL = "https://portal.amfiindia.com/spages/NAVAll.txt"

_TIMEOUT = httpx.Timeout(60.0)
_COLUMNS = 8


class AmfiError(Exception):
    def __init__(self, detail: str) -> None:
        super().__init__(detail)
        self.detail = detail


@dataclass(frozen=True)
class Scheme:
    """One row of the file: a scheme, its plan and option, and today's NAV."""

    code: str
    isin: str | None
    name: str
    plan: str
    option: str
    nav: float
    nav_date: date

    @property
    def label(self) -> str:
        """What a human recognises: the scheme, its plan, its option."""
        bits = [self.name]
        if self.plan and self.plan != "-":
            bits.append(self.plan)
        if self.option and self.option != "-":
            bits.append(self.option)
        return " · ".join(bits)


def fetch_raw() -> str:
    try:
        response = httpx.get(NAV_URL, timeout=_TIMEOUT, follow_redirects=True)
    except httpx.HTTPError as exc:
        raise AmfiError(f"AMFI unreachable: {exc}") from exc
    if response.status_code != 200:
        raise AmfiError(f"AMFI said {response.status_code}")
    return response.text


def parse(text: str) -> list[Scheme]:
    """Rows only. The file is interleaved with blank lines, fund-house names,
    and category headings — anything without eight fields and a numeric NAV is
    furniture, not data."""
    schemes: list[Scheme] = []
    for line in text.splitlines():
        if ";" not in line:
            continue
        parts = line.split(";")
        if len(parts) != _COLUMNS:
            continue
        code, isin_growth, _isin_reinvest, name, plan, option, nav_raw, date_raw = (
            p.strip() for p in parts
        )
        if not code.isdigit():
            continue  # the header row
        try:
            nav = float(nav_raw)
            # A NAV date is a calendar day, not an instant: no zone belongs
            # on it, which is exactly what .date() leaves behind.
            nav_date = datetime.strptime(date_raw, "%d-%b-%Y").date()  # noqa: DTZ007
        except ValueError:
            continue  # 'N.A.' happens on a scheme that did not publish
        schemes.append(
            Scheme(
                code=code,
                isin=isin_growth if isin_growth and isin_growth != "-" else None,
                name=name,
                plan=plan,
                option=option,
                nav=nav,
                nav_date=nav_date,
            )
        )
    return schemes


def fetch() -> list[Scheme]:
    schemes = parse(fetch_raw())
    if not schemes:
        raise AmfiError("AMFI returned a file with no scheme rows")
    log.info("amfi_fetched", schemes=len(schemes))
    return schemes


def search(schemes: list[Scheme], query: str, limit: int) -> list[Scheme]:
    """Every word must appear somewhere in the label. Crude, and exactly right
    for a field where you type 'parag flexi direct growth' and expect the one
    row you meant.

    Ranked so a shorter label wins: 'Parag Parikh Flexi Cap Fund · Direct ·
    Growth' should beat every IDCW variant of the same scheme."""
    words = [w for w in query.lower().split() if w]
    if not words:
        return []
    hits = [s for s in schemes if all(w in s.label.lower() for w in words)]
    hits.sort(key=lambda s: (len(s.label), s.label))
    return hits[:limit]
