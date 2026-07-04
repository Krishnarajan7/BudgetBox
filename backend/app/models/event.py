from datetime import date as date_

from sqlalchemy import (
    String,
    Date,
    Boolean,
    DateTime,
    ForeignKey,
    CheckConstraint,
    Index,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base

EVENT_KINDS = ("event", "birthday", "anniversary", "reminder", "important_date")


class Event(Base):
    __tablename__ = "events"
    __table_args__ = (
        CheckConstraint(
            "kind IN ('event','birthday','anniversary','reminder','important_date')",
            name="ck_events_kind",
        ),
        Index("ix_events_user_id_date", "user_id", "date"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    title: Mapped[str] = mapped_column(String(255))
    date: Mapped[date_] = mapped_column(Date, nullable=False)
    time: Mapped[str | None] = mapped_column(String(5))
    kind: Mapped[str] = mapped_column(String(20), server_default="event", default="event")
    note: Mapped[str | None] = mapped_column(String(500))
    recur_yearly: Mapped[bool] = mapped_column(Boolean, server_default="false", default=False)
    created_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
    )
