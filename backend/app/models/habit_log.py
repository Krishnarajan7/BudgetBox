from datetime import date

from sqlalchemy import Date, Boolean, ForeignKey, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class HabitLog(Base):
    __tablename__ = "habit_logs"
    __table_args__ = (
        UniqueConstraint("habit_id", "date", name="uq_habit_date"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)

    habit_id: Mapped[int] = mapped_column(
        ForeignKey("habits.id", ondelete="CASCADE"),
        index=True,
    )

    date: Mapped[date] = mapped_column(Date, nullable=False)

    completed: Mapped[bool] = mapped_column(Boolean, nullable=False)

    habit = relationship("Habit", back_populates="logs")
