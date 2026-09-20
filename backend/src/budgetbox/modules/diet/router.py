"""/v1/meals — the diet book: what was eaten, weighed on the phone."""

from datetime import date

from fastapi import APIRouter

from budgetbox.api.deps import SessionDep
from budgetbox.modules.diet import service
from budgetbox.modules.diet.schemas import MealIn, MealOut

router = APIRouter(prefix="/meals", tags=["diet"])


@router.get("")
def list_meals(
    session: SessionDep,
    from_day: date | None = None,
    to_day: date | None = None,
) -> list[MealOut]:
    rows = service.list_meals(session, from_day=from_day, to_day=to_day)
    return [MealOut.model_validate(r) for r in rows]


@router.put("/{meal_id}")
def upsert_meal(session: SessionDep, meal_id: str, data: MealIn) -> MealOut:
    return MealOut.model_validate(service.upsert(session, meal_id, data))


@router.delete("/{meal_id}", status_code=204)
def delete_meal(session: SessionDep, meal_id: str) -> None:
    service.delete(session, meal_id)
