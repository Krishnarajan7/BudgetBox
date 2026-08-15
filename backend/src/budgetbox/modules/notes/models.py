from datetime import datetime

from sqlalchemy import Boolean, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from budgetbox.db.base import Base, StampedMixin, UTCInstant, pk_id


class Note(Base, StampedMixin):
    __tablename__ = "notes"

    id: Mapped[str] = pk_id()
    title: Mapped[str] = mapped_column(String(200), default="")
    body: Mapped[str] = mapped_column(Text, default="")
    pinned: Mapped[bool] = mapped_column(Boolean, default=False)
    remind_at: Mapped[datetime | None] = mapped_column(UTCInstant(), default=None)
    completed: Mapped[bool] = mapped_column(Boolean, default=False)
    archived: Mapped[bool] = mapped_column(Boolean, default=False)
