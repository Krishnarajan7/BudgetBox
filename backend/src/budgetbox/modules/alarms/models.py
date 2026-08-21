from sqlalchemy import Boolean, CheckConstraint, String
from sqlalchemy.orm import Mapped, mapped_column

from budgetbox.db.base import Base, StampedMixin, pk_id


class Alarm(Base, StampedMixin):
    """An alarm that rings. The ringing itself is the phone's job — this table
    exists so a reinstalled phone gets its mornings back.

    `days` is a weekday bitmask: Monday is bit 0 … Sunday is bit 6. Zero means
    it rings once, at the next occurrence of the time, then switches itself off.
    """

    __tablename__ = "alarms"
    __table_args__ = (
        CheckConstraint("minute_of_day BETWEEN 0 AND 1439", name="minute_range"),
        CheckConstraint("days BETWEEN 0 AND 127", name="days_mask"),
        CheckConstraint("snooze_minutes BETWEEN 1 AND 60", name="snooze_range"),
    )

    id: Mapped[str] = pk_id()
    label: Mapped[str] = mapped_column(String(60), default="")
    minute_of_day: Mapped[int]
    days: Mapped[int] = mapped_column(default=0)
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    snooze_minutes: Mapped[int] = mapped_column(default=9)
    vibrate: Mapped[bool] = mapped_column(Boolean, default=True)
