import datetime as dt

from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column

from budgetbox.db.base import Base, DayKey, StampedMixin


class AccountSnapshot(Base, StampedMixin):
    """End-of-IST-day balance per account. Derivable (and re-derived) from anchors +
    ledger at any time, so this is a cache with an exact rebuild, not a source of
    truth. Feeds the net worth chart and per-account sparklines."""

    __tablename__ = "account_snapshots"

    account_id: Mapped[str] = mapped_column(ForeignKey("accounts.id"), primary_key=True)
    date: Mapped[dt.date] = mapped_column(DayKey(), primary_key=True)
    balance_paise: Mapped[int]
