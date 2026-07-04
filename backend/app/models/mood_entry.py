from datetime import date

from sqlalchemy import Date, Integer, String, ForeignKey, Index, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class MoodEntry(Base):
    __tablename__ = "mood_entries"

    __table_args__ = (
        UniqueConstraint("user_id", "date", name="uq_mood_entries_user_date"),
        Index("ix_mood_entries_user_id_date", "user_id", "date"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)

    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )

    date: Mapped[date] = mapped_column(Date, nullable=False)

    mood: Mapped[int] = mapped_column(Integer, nullable=False)

    note: Mapped[str | None] = mapped_column(String(500), nullable=True)
