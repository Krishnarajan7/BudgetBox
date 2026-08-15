import datetime as dt

from sqlalchemy import CheckConstraint, Text
from sqlalchemy.orm import Mapped, mapped_column

from budgetbox.db.base import Base, DayKey, StampedMixin


class JournalEntry(Base, StampedMixin):
    """One entry per IST day; writing again the same day replaces it (upsert)."""

    __tablename__ = "journal_entries"
    __table_args__ = (
        CheckConstraint("mood IS NULL OR mood BETWEEN 1 AND 9", name="mood_range"),
        CheckConstraint("energy IS NULL OR energy BETWEEN 1 AND 9", name="energy_range"),
    )

    date: Mapped[dt.date] = mapped_column(DayKey(), primary_key=True)
    body: Mapped[str] = mapped_column(Text, default="")
    # The felt field: mood is pleasantness 1 rough … 9 good (pre-0010 rows
    # held 1…5 and were re-ruled as (m-1)*2+1); energy is 1 still … 9 wired,
    # null on marks made before the field existed.
    mood: Mapped[int | None] = mapped_column(default=None)
    energy: Mapped[int | None] = mapped_column(default=None)
    feel_word: Mapped[str | None] = mapped_column(Text, default=None)  # 'frayed', 'settled', …
    # The check-in's second breath: why it sat that way, and the context
    # chips (comma-joined — 'working,alone,home').
    feel_why: Mapped[str | None] = mapped_column(Text, default=None)
    feel_tags: Mapped[str | None] = mapped_column(Text, default=None)
