from sqlalchemy import String, Text
from sqlalchemy.orm import Mapped, mapped_column

from budgetbox.db.base import Base, StampedMixin


class Setting(Base, StampedMixin):
    """Small KV store mirroring the app's Settings table: name, salary_day,
    setup_done, theme_mode… Values are strings; typed accessors live in the service."""

    __tablename__ = "settings"

    key: Mapped[str] = mapped_column(String(40), primary_key=True)
    value: Mapped[str] = mapped_column(Text)
