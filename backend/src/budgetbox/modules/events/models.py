import datetime as dt
import enum

from sqlalchemy import Boolean, CheckConstraint, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from budgetbox.db.base import Base, DayKey, StampedMixin, pk_id, str_enum


class EventRepeat(enum.StrEnum):
    NONE = "none"
    YEARLY = "yearly"


class Event(Base, StampedMixin):
    """Calendar events: an anchor date plus optional yearly repeat. Occurrence
    expansion lives in domain/events.py."""

    __tablename__ = "events"
    __table_args__ = (
        CheckConstraint(
            "time_minutes IS NULL OR time_minutes BETWEEN 0 AND 1439", name="time_minutes_range"
        ),
    )

    id: Mapped[str] = pk_id()
    title: Mapped[str] = mapped_column(String(120))
    note: Mapped[str | None] = mapped_column(Text, default=None)
    date: Mapped[dt.date] = mapped_column(DayKey())  # anchor
    time_minutes: Mapped[int | None] = mapped_column(default=None)  # null = all-day
    repeat: Mapped[EventRepeat] = mapped_column(
        str_enum(EventRepeat, "event_repeat"), default=EventRepeat.NONE
    )
    archived: Mapped[bool] = mapped_column(Boolean, default=False)
