"""The slate: money lent to people, and money they lend back.

Lending is not spending — the money is still yours, it has only moved out of
reach. So every slate entry moves real money as a *transfer* between the
account it came from and one asset account named 'On the slate'. Spending
stays honest, net worth stays flat, and one invariant holds forever:

    sum(every person's balance) == the 'On the slate' account balance

The only moment lending becomes an expense is the moment it is let go."""

import datetime as dt
import enum

from sqlalchemy import Boolean, CheckConstraint, ForeignKey, Index, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from budgetbox.db.base import Base, StampedMixin, UTCInstant, pk_id, str_enum


class SlateKind(enum.StrEnum):
    """Direction, from the book-keeper's side.

    LENT/REPAID are one loop: money out, money back. BORROWED/SETTLED are the
    mirror, for when Krish is the one who owes. FORGIVEN closes a lend that is
    never coming back; WRITTEN_OFF closes a borrow the other side let go.
    """

    LENT = "lent"
    REPAID = "repaid"
    BORROWED = "borrowed"
    SETTLED = "settled"
    FORGIVEN = "forgiven"
    WRITTEN_OFF = "written_off"


#: What each kind does to a person's balance, in paise, from your side:
#: positive means "they owe you".
KIND_SIGN: dict[SlateKind, int] = {
    SlateKind.LENT: 1,
    SlateKind.REPAID: -1,
    SlateKind.BORROWED: -1,
    SlateKind.SETTLED: 1,
    SlateKind.FORGIVEN: -1,
    SlateKind.WRITTEN_OFF: 1,
}

#: The kinds that close a balance rather than move money between pockets.
#: These become an expense (forgiven) or income (written off) at the moment
#: they are recorded — never before.
CLOSING_KINDS = (SlateKind.FORGIVEN, SlateKind.WRITTEN_OFF)


class SlatePerson(Base, StampedMixin):
    """One running slate per person, not per loan: you lend a friend twice and
    they pay back once, and that is one relationship carrying one number."""

    __tablename__ = "slate_people"
    __table_args__ = (Index("ix_slate_people_name", "name"),)

    id: Mapped[str] = pk_id()
    name: Mapped[str] = mapped_column(String(60))
    # Free text: 'sister', 'college', whatever makes the row recognisable.
    relation: Mapped[str | None] = mapped_column(String(40), default=None)
    note: Mapped[str | None] = mapped_column(Text, default=None)
    archived: Mapped[bool] = mapped_column(Boolean, default=False)


class SlateEntry(Base, StampedMixin):
    """One movement on someone's slate. `txn_id` is the ledger line that
    actually moved the money — always present except on a closing entry that
    was recorded against an already-settled book."""

    __tablename__ = "slate_entries"
    __table_args__ = (
        CheckConstraint("amount_paise > 0", name="amount_positive"),
        Index("ix_slate_entries_person_at", "person_id", "at"),
    )

    id: Mapped[str] = pk_id()
    person_id: Mapped[str] = mapped_column(ForeignKey("slate_people.id"))
    kind: Mapped[SlateKind] = mapped_column(str_enum(SlateKind, "slate_kind"))
    amount_paise: Mapped[int]
    at: Mapped[dt.datetime] = mapped_column(UTCInstant())
    note: Mapped[str | None] = mapped_column(Text, default=None)
    txn_id: Mapped[str | None] = mapped_column(ForeignKey("txns.id"), default=None)
