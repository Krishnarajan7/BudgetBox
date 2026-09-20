from datetime import date, datetime
from typing import Annotated

from pydantic import Field

from budgetbox.api.schemas import APIModel, Instant
from budgetbox.modules.diet.models import MealSlot

Name = Annotated[str, Field(strict=True, min_length=1, max_length=120)]
FoodKey = Annotated[str | None, Field(max_length=24)]
# The serving's nutrients, as the phone worked them out. A JSON object of
# short keys to numbers; stored as text, never interpreted here.
Facts = Annotated[str | None, Field(max_length=2000)]
Note = Annotated[str | None, Field(max_length=280)]


class MealIn(APIModel):
    date: date
    slot: MealSlot
    food_key: FoodKey = None
    name: Name
    servings: Annotated[float, Field(ge=0, le=50)] = 1.0
    grams: Annotated[float | None, Field(ge=0, le=5000)] = None
    facts: Facts = None
    skipped: bool = False
    note: Note = None
    at: Instant


class MealOut(APIModel):
    id: str
    date: date
    slot: MealSlot
    food_key: str | None
    name: str
    servings: float
    grams: float | None
    facts: str | None
    skipped: bool
    note: str | None
    at: datetime
    created_at: datetime
    updated_at: datetime
