"""The folio: money moved out of a bank and into funds.

Buying a fund is not spending — the money changes shape, not owner. So every
contribution is a *transfer* from a real pocket into the one asset account the
book already calls 'SIP / mutual funds', exactly as lending moves money onto
the slate.

What makes a fund different from a slate is that it *moves on its own*. A loan
of ₹5,000 is ₹5,000 owed; ₹5,000 of units is whatever the market says today.
So a holding keeps two numbers that are never the same thing:

- **cost** — what was actually paid in, which only changes when money moves
- **value** — units times the latest NAV, which changes while you sleep

The gap between them is the only return figure this book will ever show, and
it is arithmetic rather than opinion.
"""

import datetime as dt
import enum

from sqlalchemy import Boolean, CheckConstraint, ForeignKey, Index, Numeric, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from budgetbox.db.base import Base, DayKey, StampedMixin, UTCInstant, pk_id, str_enum

#: Units are fractional and small differences compound, so they are stored as
#: exact decimal text rather than float: 110.61947 units is not 110.61946.
Units = Numeric(20, 5, asdecimal=True)


class FolioEntryKind(enum.StrEnum):
    """SIP and LUMPSUM both buy; they differ only in the rhythm that produced
    them, which is worth keeping because 'what do my SIPs add up to' is a real
    question. REDEEM sells back."""

    SIP = "sip"
    LUMPSUM = "lumpsum"
    REDEEM = "redeem"


#: What each kind does to the units held.
KIND_SIGN: dict[FolioEntryKind, int] = {
    FolioEntryKind.SIP: 1,
    FolioEntryKind.LUMPSUM: 1,
    FolioEntryKind.REDEEM: -1,
}

BUY_KINDS = (FolioEntryKind.SIP, FolioEntryKind.LUMPSUM)


class Fund(Base, StampedMixin):
    """One holding. `scheme_code` ties it to AMFI so its worth keeps itself up
    to date; without one the fund is valued by hand (a PPF, gold, an RSU) and
    `manual_value_paise` carries the last figure given."""

    __tablename__ = "funds"
    __table_args__ = (Index("ix_funds_scheme_code", "scheme_code"),)

    id: Mapped[str] = pk_id()
    name: Mapped[str] = mapped_column(String(160))
    scheme_code: Mapped[str | None] = mapped_column(String(12), default=None)
    # Latest NAV seen for this scheme, and the day AMFI published it.
    nav: Mapped[float | None] = mapped_column(default=None)
    nav_date: Mapped[dt.date | None] = mapped_column(DayKey(), default=None)
    # For a fund AMFI does not price.
    manual_value_paise: Mapped[int | None] = mapped_column(default=None)
    manual_value_at: Mapped[dt.datetime | None] = mapped_column(UTCInstant(), default=None)
    note: Mapped[str | None] = mapped_column(Text, default=None)
    archived: Mapped[bool] = mapped_column(Boolean, default=False)
    sort_order: Mapped[int] = mapped_column(default=0)


class FolioEntry(Base, StampedMixin):
    """One purchase or redemption. `units` is what the money actually bought at
    that day's NAV — the number that makes a fund's worth computable later
    without re-deriving it from prices that have since moved."""

    __tablename__ = "folio_entries"
    __table_args__ = (
        CheckConstraint("amount_paise > 0", name="amount_positive"),
        Index("ix_folio_entries_fund_at", "fund_id", "at"),
    )

    id: Mapped[str] = pk_id()
    fund_id: Mapped[str] = mapped_column(ForeignKey("funds.id"))
    kind: Mapped[FolioEntryKind] = mapped_column(str_enum(FolioEntryKind, "folio_entry_kind"))
    amount_paise: Mapped[int]
    # Null when the fund is priced by hand and no NAV was known at the time.
    units: Mapped[float | None] = mapped_column(Units, default=None)
    nav: Mapped[float | None] = mapped_column(default=None)
    at: Mapped[dt.datetime] = mapped_column(UTCInstant())
    note: Mapped[str | None] = mapped_column(Text, default=None)
    txn_id: Mapped[str | None] = mapped_column(ForeignKey("txns.id"), default=None)
