import datetime as dt
import enum

from sqlalchemy import Boolean, Float, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from budgetbox.db.base import Base, DayKey, StampedMixin, UTCInstant, pk_id, str_enum


class MealSlot(enum.StrEnum):
    breakfast = "breakfast"
    lunch = "lunch"
    snack = "snack"
    dinner = "dinner"


class Meal(Base, StampedMixin):
    """One dish eaten — the diet book's row.

    The phone weighs the dish against its bundled food table and sends the
    result along as `facts` (a JSON object of nutrient amounts for the serving
    as eaten). The server stores that verbatim and never re-derives it: a
    catalogue revision on the phone must not rewrite a day already eaten, and
    the server has no catalogue of its own to disagree with.

    `skipped` is a deliberate empty sitting — different evidence from a sitting
    the book never heard about, which is why it is a row and not an absence.
    """

    __tablename__ = "meals"

    id: Mapped[str] = pk_id()
    date: Mapped[dt.date] = mapped_column(DayKey(), index=True)
    slot: Mapped[MealSlot] = mapped_column(str_enum(MealSlot, "meal_slot"))
    food_key: Mapped[str | None] = mapped_column(String(24), default=None)
    name: Mapped[str] = mapped_column(String(120))
    servings: Mapped[float] = mapped_column(Float, default=1.0)
    grams: Mapped[float | None] = mapped_column(Float, default=None)
    facts: Mapped[str | None] = mapped_column(Text, default=None)
    skipped: Mapped[bool] = mapped_column(Boolean, default=False)
    note: Mapped[str | None] = mapped_column(Text, default=None)
    at: Mapped[dt.datetime] = mapped_column(UTCInstant())
