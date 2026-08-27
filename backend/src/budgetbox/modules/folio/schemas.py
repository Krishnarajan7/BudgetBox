from datetime import date, datetime
from typing import Annotated

from pydantic import Field

from budgetbox.api.schemas import APIModel, Instant, PositivePaise
from budgetbox.modules.folio.models import FolioEntryKind

Name = Annotated[str, Field(min_length=1, max_length=160)]


class SchemeOut(APIModel):
    """A row of AMFI's file, for the search field."""

    code: str
    label: str
    nav: float
    nav_date: date


class FundIn(APIModel):
    name: Name
    # An AMFI scheme code makes the fund price itself; without one it is
    # valued by hand.
    scheme_code: str | None = None
    note: str | None = None


class FundPatch(APIModel):
    name: Name | None = None
    scheme_code: str | None = None
    note: str | None = None
    archived: bool | None = None
    sort_order: int | None = None


class EntryOut(APIModel):
    id: str
    fund_id: str
    kind: FolioEntryKind
    amount_paise: int
    units: float | None
    nav: float | None
    at: datetime
    note: str | None
    txn_id: str | None


class FundOut(APIModel):
    id: str
    name: str
    scheme_code: str | None
    note: str | None
    archived: bool

    # What was paid in, less what has been taken out at its cost. Moves only
    # when money moves.
    cost_paise: int
    # units x latest NAV, or the hand-given figure. Moves on its own.
    value_paise: int
    # value - cost. The only return figure this book shows.
    gain_paise: int
    # gain / cost, as a fraction. Null when nothing has been put in.
    return_ratio: float | None

    units: float
    nav: float | None
    nav_date: date | None
    # True when AMFI prices this fund; false when the figure was typed in.
    priced: bool
    manual_value_at: datetime | None

    entries: int
    sip_count: int
    sip_paise: int
    first_at: datetime | None
    last_at: datetime | None


class FolioPoint(APIModel):
    """One day of the folio's two lines. `cost` is a staircase that only steps
    when money went in; `value` wanders. The gap between them is the gain, and
    drawing both is the whole point of the chart."""

    date: date
    cost_paise: int
    value_paise: int


class OverviewOut(APIModel):
    cost_paise: int
    value_paise: int
    gain_paise: int
    return_ratio: float | None
    funds: int
    # This month's contributions, so the page can say what has gone in.
    month_paise: int
    # The oldest NAV among priced funds — how stale the worth figure is.
    priced_upto: date | None
    unpriced_funds: int


class ContributeIn(APIModel):
    """Money in. `account_id` is the pocket it leaves — the bank, usually."""

    amount_paise: PositivePaise
    account_id: str
    kind: FolioEntryKind = FolioEntryKind.SIP
    at: Instant | None = None
    note: str | None = None
    # Override the NAV used to price the units (a backdated SIP buys at that
    # day's price, not today's). Null takes the fund's latest.
    nav: float | None = None


class RedeemIn(APIModel):
    amount_paise: PositivePaise
    account_id: str
    at: Instant | None = None
    note: str | None = None
    nav: float | None = None


class ValueIn(APIModel):
    """The hand-given worth of a fund AMFI does not price."""

    value_paise: PositivePaise
    at: Instant | None = None
