import enum
from datetime import datetime

from sqlalchemy import Boolean, ForeignKey, Index, String
from sqlalchemy.orm import Mapped, mapped_column

from budgetbox.db.base import Base, StampedMixin, UTCInstant, pk_id, str_enum


class AccountKind(enum.StrEnum):
    BANK = "bank"
    UPI = "upi"
    CASH = "cash"
    CARD = "card"
    ASSET = "asset"
    LIABILITY = "liability"


class Account(Base, StampedMixin):
    """No stored balance: balances derive from the latest anchor plus the ledger,
    so drift between a cached number and the truth is structurally impossible."""

    __tablename__ = "accounts"

    id: Mapped[str] = pk_id()
    name: Mapped[str] = mapped_column(String(60))
    kind: Mapped[AccountKind] = mapped_column(str_enum(AccountKind, "account_kind"))
    sort_order: Mapped[int] = mapped_column(default=0)
    archived: Mapped[bool] = mapped_column(Boolean, default=False)


class BalanceAnchor(Base, StampedMixin):
    """A user-confirmed balance at an instant (setup, or the update-balance sheet).
    The latest anchor's `at` is the account's as-of staleness cue."""

    __tablename__ = "balance_anchors"
    __table_args__ = (Index("ix_balance_anchors_account_at", "account_id", "at"),)

    id: Mapped[str] = pk_id()
    account_id: Mapped[str] = mapped_column(ForeignKey("accounts.id"))
    at: Mapped[datetime] = mapped_column(UTCInstant())
    balance_paise: Mapped[int]
