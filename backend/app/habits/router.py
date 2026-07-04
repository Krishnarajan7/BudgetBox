from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.auth.deps import get_current_user
from app.models.user import User

from app.habits.schemas import HabitCreate, HabitLogPatch, HabitUpdate
from app.habits.service import (
    create_habit,
    list_habits,
    delete_habit,
    habit_insights,
    habit_financial_impact,
    patch_habit_log,
    get_habit_log_today,
    update_habit,
)


router = APIRouter(prefix="/habits", tags=["habits"])


@router.post("", status_code=status.HTTP_201_CREATED)
async def create_habit_endpoint(
    data: HabitCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await create_habit(db, user.id, data.name)


@router.get("")
async def list_user_habits(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await list_habits(db, user.id)


@router.delete("/{habit_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_habit_endpoint(
    habit_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await delete_habit(db, user.id, habit_id)


@router.get("/{habit_id}/insights")
async def habit_insights_endpoint(
    habit_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await habit_insights(db, user.id, habit_id)


@router.get("/{habit_id}/impact")
async def habit_financial_impact_endpoint(
    habit_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await habit_financial_impact(db, habit_id, user.id)


@router.patch("/{habit_id}/logs/today")
async def patch_today_habit_log(
    habit_id: int,
    data: HabitLogPatch,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    log = await patch_habit_log(db, user.id, habit_id, data)
    return {
        "habit_id": habit_id,
        "date": log.date,
        "completed": log.completed,
    }


@router.get("/{habit_id}/logs/today")
async def get_today_habit_log(
    habit_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await get_habit_log_today(db, user.id, habit_id)


@router.patch("/{habit_id}")
async def update_habit_endpoint(
    habit_id: int,
    data: HabitUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await update_habit(db, user.id, habit_id, data)
