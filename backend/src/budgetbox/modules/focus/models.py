import datetime as dt
import enum

from sqlalchemy import Boolean, CheckConstraint, String
from sqlalchemy.orm import Mapped, mapped_column

from budgetbox.db.base import Base, StampedMixin, UTCInstant, pk_id, str_enum


class FocusKind(enum.StrEnum):
    WORK = "work"
    REST = "rest"


class FocusSession(Base, StampedMixin):
    __tablename__ = "focus_sessions"
    __table_args__ = (CheckConstraint("minutes > 0", name="minutes_positive"),)

    id: Mapped[str] = pk_id()
    started_at: Mapped[dt.datetime] = mapped_column(UTCInstant())
    minutes: Mapped[int]
    kind: Mapped[FocusKind] = mapped_column(str_enum(FocusKind, "focus_kind"))
    completed: Mapped[bool] = mapped_column(Boolean, default=False)
    label: Mapped[str | None] = mapped_column(String(60), default=None)
