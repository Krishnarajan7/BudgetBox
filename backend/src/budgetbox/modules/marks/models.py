import datetime as dt

from sqlalchemy import String, Text
from sqlalchemy.orm import Mapped, mapped_column

from budgetbox.db.base import Base, DayKey, StampedMixin, UTCInstant, pk_id


class DayMark(Base, StampedMixin):
    """One small daily truth that isn't money: a habit kept ('bath', 'gym'),
    a meal eaten ('meal', with the food in `note`), or the one mark that
    counts by its absence ('slip' — a clean day is a day with no slip row).

    `kind` is a free string on purpose: a habit the app invents tomorrow needs
    no migration here, and the habit *definitions* travel as a setting. A
    counted habit writes one row per tap, so the same (date, kind) can repeat
    — which is why this table is id-keyed and not (date, kind)-keyed.
    """

    __tablename__ = "day_marks"

    id: Mapped[str] = pk_id()
    date: Mapped[dt.date] = mapped_column(DayKey(), index=True)
    kind: Mapped[str] = mapped_column(String(32))
    note: Mapped[str | None] = mapped_column(Text, default=None)
    # The moment the mark was made — a meal at 13:04 is different evidence
    # from a meal at 23:40, and the app orders the day's strip by it.
    at: Mapped[dt.datetime] = mapped_column(UTCInstant())
