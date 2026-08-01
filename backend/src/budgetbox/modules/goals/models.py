import datetime as dt
import enum

from sqlalchemy import Boolean, CheckConstraint, String
from sqlalchemy.orm import Mapped, mapped_column

from budgetbox.db.base import Base, DayKey, StampedMixin, pk_id, str_enum


class GoalKind(enum.StrEnum):
    SAVE = "save"  # build toward a target
    CLEAR = "clear"  # pay down a debt


class Goal(Base, StampedMixin):
    """A goal is a view over goal-tagged txns — never a separate ledger."""

    __tablename__ = "goals"
    __table_args__ = (CheckConstraint("target_paise > 0", name="target_positive"),)

    id: Mapped[str] = pk_id()
    name: Mapped[str] = mapped_column(String(60))
    target_paise: Mapped[int]
    kind: Mapped[GoalKind] = mapped_column(str_enum(GoalKind, "goal_kind"))
    target_date: Mapped[dt.date | None] = mapped_column(DayKey(), default=None)
    monthly_paise: Mapped[int | None] = mapped_column(default=None)
    archived: Mapped[bool] = mapped_column(Boolean, default=False)
