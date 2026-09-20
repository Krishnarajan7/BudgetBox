"""The diet book's rows. Thin on purpose: the meaning of a dish lives on the
phone (its food table, its targets); this stores, lists and drops."""

import datetime as dt

from sqlalchemy import select
from sqlalchemy.orm import Session

from budgetbox.core.errors import NotFound
from budgetbox.core.ids import require_uuid
from budgetbox.modules.diet.models import Meal
from budgetbox.modules.diet.schemas import MealIn


def list_meals(
    session: Session,
    *,
    from_day: dt.date | None = None,
    to_day: dt.date | None = None,
) -> list[Meal]:
    """Meals in the closed day range, oldest first. No range means the whole
    record — a restoring phone wants all of it."""
    stmt = select(Meal).order_by(Meal.date, Meal.at, Meal.id)
    if from_day is not None:
        stmt = stmt.where(Meal.date >= from_day)
    if to_day is not None:
        stmt = stmt.where(Meal.date <= to_day)
    return list(session.scalars(stmt))


def get(session: Session, meal_id: str) -> Meal:
    row = session.get(Meal, meal_id)
    if row is None:
        raise NotFound(f"no meal {meal_id}")
    return row


def upsert(session: Session, meal_id: str, data: MealIn) -> Meal:
    meal_id = require_uuid(meal_id)
    row = session.get(Meal, meal_id)
    if row is None:
        row = Meal(id=meal_id)
        session.add(row)
    row.date = data.date
    row.slot = data.slot
    row.food_key = data.food_key
    row.name = data.name
    row.servings = data.servings
    row.grams = data.grams
    row.facts = data.facts
    row.skipped = data.skipped
    row.note = data.note
    row.at = data.at
    session.commit()
    return row


def delete(session: Session, meal_id: str) -> None:
    """Hard delete — striking a dish off the page removes it, and the tombstone
    in change_events tells the other phone to do the same."""
    row = get(session, meal_id)
    session.delete(row)
    session.commit()
