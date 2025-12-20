from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from datetime import date

from app.core.database import get_db
from app.auth.deps import get_current_user
from app.models.user import User
from app.models.habit import Habit
from app.models.habit_log import HabitLog

from app.habits.service import habit_insights, habit_financial_impact


router = APIRouter(prefix="/habits", tags=["habits"])


@router.post("")
async def create_habit(
    name: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    habit = Habit(user_id=user.id, name=name)
    db.add(habit)
    await db.commit()
    await db.refresh(habit)
    return habit


@router.post("/{habit_id}/complete")
async def complete_habit(
    habit_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    log = HabitLog(
        habit_id=habit_id,
        date=date.today(),
        completed=True,
    )
    db.add(log)
    await db.commit()
    return {"status": "completed"}


@router.get("/{habit_id}/insights")
async def insights(
    habit_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await habit_insights(db, habit_id)



@router.get("/{habit_id}/impact")
async def financial_impact(
    habit_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await habit_financial_impact(db, habit_id, user.id)