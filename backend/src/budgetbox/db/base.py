"""Declarative base + the type decorators that pin the storage conventions:
UTC ISO text for instants, 'yyyy-MM-dd' text for calendar days, string enums
with CHECK constraints. Money columns are plain INTEGER paise."""

import enum
from datetime import UTC, date, datetime

from sqlalchemy import MetaData, String, types
from sqlalchemy.engine import Dialect
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

from budgetbox.core.time import now_utc

NAMING_CONVENTION = {
    "ix": "ix_%(column_0_label)s",
    "uq": "uq_%(table_name)s_%(column_0_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}


class Base(DeclarativeBase):
    metadata = MetaData(naming_convention=NAMING_CONVENTION)


class UTCInstant(types.TypeDecorator[datetime]):
    """tz-aware datetime <-> ISO-8601 UTC text. Naive datetimes are a bug: rejected."""

    impl = String(32)
    cache_ok = True

    def process_bind_param(self, value: datetime | None, dialect: Dialect) -> str | None:
        if value is None:
            return None
        if value.tzinfo is None:
            raise ValueError("naive datetime bound to UTCInstant column")
        return value.astimezone(UTC).isoformat(timespec="microseconds")

    def process_result_value(self, value: str | None, dialect: Dialect) -> datetime | None:
        return None if value is None else datetime.fromisoformat(value)


class DayKey(types.TypeDecorator[date]):
    """datetime.date <-> 'yyyy-MM-dd' text. datetime is a date subclass, so an exact
    type check keeps instants from silently leaking into day columns."""

    impl = String(10)
    cache_ok = True

    def process_bind_param(self, value: date | None, dialect: Dialect) -> str | None:
        if value is None:
            return None
        if type(value) is not date:
            raise ValueError(f"DayKey column takes datetime.date, got {type(value).__name__}")
        return value.isoformat()

    def process_result_value(self, value: str | None, dialect: Dialect) -> date | None:
        return None if value is None else date.fromisoformat(value)


def _enum_values(enum_cls: type[enum.Enum]) -> list[str]:
    return [str(member.value) for member in enum_cls]


def str_enum(enum_cls: type[enum.StrEnum], name: str) -> types.Enum:
    """String-stored enum with a named CHECK constraint. Values (not ordinals) hit disk."""
    return types.Enum(
        enum_cls,
        name=name,
        native_enum=False,
        create_constraint=True,
        validate_strings=True,
        length=24,
        values_callable=_enum_values,
    )


class StampedMixin:
    """created_at/updated_at on every entity; updated_at feeds GET /v1/changes."""

    created_at: Mapped[datetime] = mapped_column(UTCInstant(), default=now_utc)
    updated_at: Mapped[datetime] = mapped_column(UTCInstant(), default=now_utc, onupdate=now_utc)


def pk_id() -> Mapped[str]:
    """Client- or server-minted UUIDv7 primary key (TEXT)."""
    return mapped_column(String(36), primary_key=True)
