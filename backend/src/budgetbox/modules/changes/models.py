import enum
from datetime import datetime

from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column

from budgetbox.db.base import Base, UTCInstant, str_enum


class ChangeOperation(enum.StrEnum):
    UPSERT = "upsert"
    DELETE = "delete"


class ChangeEvent(Base):
    """Append-only synchronization cursor.

    SQLite triggers write this table for every sync-visible mutation. Keeping
    deletion tombstones here is what lets another phone remove a row that no
    longer exists in its source table.
    """

    __tablename__ = "change_events"

    sequence: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    resource: Mapped[str] = mapped_column(String(40), index=True)
    resource_id: Mapped[str] = mapped_column(String(40))
    operation: Mapped[ChangeOperation] = mapped_column(
        str_enum(ChangeOperation, "change_operation")
    )
    changed_at: Mapped[datetime] = mapped_column(UTCInstant())
