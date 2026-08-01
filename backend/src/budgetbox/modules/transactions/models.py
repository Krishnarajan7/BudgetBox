import datetime as dt
import enum

from sqlalchemy import CheckConstraint, ForeignKey, Index, String, Text, text
from sqlalchemy.orm import Mapped, mapped_column

from budgetbox.db.base import Base, DayKey, StampedMixin, UTCInstant, pk_id, str_enum


class TxnType(enum.StrEnum):
    EXPENSE = "expense"
    INCOME = "income"
    TRANSFER = "transfer"


class ActivityAction(enum.StrEnum):
    CREATED = "created"
    EDITED = "edited"
    DELETED = "deleted"


class Txn(Base, StampedMixin):
    """Amounts are always positive; type carries direction. Transfers reference the
    receiving account and never a category. goal_id/recurring_id gain FKs when those
    tables land (phase 3/4 migrations)."""

    __tablename__ = "txns"
    __table_args__ = (
        CheckConstraint("amount_paise > 0", name="amount_positive"),
        CheckConstraint("(type = 'transfer') = (to_account_id IS NOT NULL)", name="transfer_shape"),
        CheckConstraint(
            "type != 'transfer' OR category_id IS NULL", name="transfer_has_no_category"
        ),
        Index("ix_txns_at_id", "at", "id"),
        # Hard guard: one materialized txn per (recurring, due instant).
        Index(
            "uq_txns_recurring_due",
            "recurring_id",
            "at",
            unique=True,
            sqlite_where=text("recurring_id IS NOT NULL"),
        ),
    )

    id: Mapped[str] = pk_id()
    amount_paise: Mapped[int]
    type: Mapped[TxnType] = mapped_column(str_enum(TxnType, "txn_type"))
    category_id: Mapped[str | None] = mapped_column(ForeignKey("categories.id"), default=None)
    account_id: Mapped[str] = mapped_column(ForeignKey("accounts.id"))
    to_account_id: Mapped[str | None] = mapped_column(ForeignKey("accounts.id"), default=None)
    title: Mapped[str] = mapped_column(String(120))
    note: Mapped[str | None] = mapped_column(Text, default=None)
    at: Mapped[dt.datetime] = mapped_column(UTCInstant())
    goal_id: Mapped[str | None] = mapped_column(ForeignKey("goals.id"), default=None)
    recurring_id: Mapped[str | None] = mapped_column(ForeignKey("recurrings.id"), default=None)


class Pinned(Base, StampedMixin):
    """A one-tap repeat on Today: title + amount + category + account, stamped into
    a fresh txn on tap."""

    __tablename__ = "pinneds"

    id: Mapped[str] = pk_id()
    title: Mapped[str] = mapped_column(String(120))
    amount_paise: Mapped[int]
    category_id: Mapped[str] = mapped_column(ForeignKey("categories.id"))
    account_id: Mapped[str] = mapped_column(ForeignKey("accounts.id"))
    sort_order: Mapped[int] = mapped_column(default=0)


class DaySeal(Base, StampedMixin):
    """The once-a-day 'close the day' ritual."""

    __tablename__ = "day_seals"

    date: Mapped[dt.date] = mapped_column(DayKey(), primary_key=True)
    sealed_at: Mapped[dt.datetime] = mapped_column(UTCInstant())


class Activity(Base, StampedMixin):
    """Undo log for txn mutations, written in the same transaction as the mutation.
    The snapshot is the wire-schema JSON needed to reverse the action: the before-image
    for edits, the row itself for creates/deletes. Undo consumes the row."""

    __tablename__ = "activities"

    id: Mapped[str] = pk_id()
    txn_id: Mapped[str] = mapped_column(String(36))  # no FK: the txn may be deleted
    action: Mapped[ActivityAction] = mapped_column(str_enum(ActivityAction, "activity_action"))
    snapshot: Mapped[str] = mapped_column(Text)
    at: Mapped[dt.datetime] = mapped_column(UTCInstant())
