import datetime as dt

from sqlalchemy import CheckConstraint, Text
from sqlalchemy.orm import Mapped, mapped_column

from budgetbox.db.base import Base, DayKey, StampedMixin


class JournalEntry(Base, StampedMixin):
    """One entry per IST day; writing again the same day replaces it (upsert)."""

    __tablename__ = "journal_entries"
    __table_args__ = (CheckConstraint("mood IS NULL OR mood BETWEEN 1 AND 5", name="mood_range"),)

    date: Mapped[dt.date] = mapped_column(DayKey(), primary_key=True)
    body: Mapped[str] = mapped_column(Text, default="")
    mood: Mapped[int | None] = mapped_column(default=None)  # 1 rough … 5 great
