from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.habits.schemas import HabitCreate, HabitResponse, HabitLogResponse
from app.habits.service import create_habit, complete_habit_for_today
from app.core.database import get_db
from app.auth.deps import get_current_user
from app.models.user import User

from app.income.schemas import IncomeUpdate
from app.income.service import update_income

router = APIRouter(prefix="/habits", tags=["habits"])


@router.post("", response_model=HabitResponse, status_code=status.HTTP_201_CREATED)
async def create(
    data: HabitCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    habit = await create_habit(db, user.id, data.name)
    return habit


@router.post("/{habit_id}/complete", response_model=HabitLogResponse)
async def complete_today(
    habit_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    log = await complete_habit_for_today(db, user.id, habit_id)
    return log


@router.patch("/{income_id}")
async def patch_income(
    income_id: int,
    data: IncomeUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    income = await update_income(db, user.id, income_id, data)
    return {
        "id": income.id,
        "amount": float(income.amount),
        "note": income.note,
        "occurred_at": income.occurred_at,
    }