from datetime import date
from decimal import Decimal

from sqlalchemy import Date, Integer, Numeric, String, ForeignKey, Index, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class SleepEntry(Base):
    __tablename__ = "sleep_entries"

    __table_args__ = (
        UniqueConstraint("user_id", "date", name="uq_sleep_entries_user_date"),
        Index("ix_sleep_entries_user_id_date", "user_id", "date"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)

    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )

    date: Mapped[date] = mapped_column(Date, nullable=False)

    hours: Mapped[Decimal] = mapped_column(Numeric(4, 2), nullable=False)

    quality: Mapped[int | None] = mapped_column(Integer, nullable=True)

    bedtime: Mapped[str | None] = mapped_column(String(5), nullable=True)

    wake_time: Mapped[str | None] = mapped_column(String(5), nullable=True)
