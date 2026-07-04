from datetime import date

from sqlalchemy import Date, Integer, ForeignKey, Index, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class WaterLog(Base):
    __tablename__ = "water_logs"

    __table_args__ = (
        UniqueConstraint("user_id", "date", name="uq_water_logs_user_date"),
        Index("ix_water_logs_user_id_date", "user_id", "date"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)

    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )

    date: Mapped[date] = mapped_column(Date, nullable=False)

    glasses: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")

    goal: Mapped[int] = mapped_column(Integer, nullable=False, server_default="8")
