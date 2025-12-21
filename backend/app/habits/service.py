from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update
from datetime import date

from app.models.habit import Habit
from app.models.habit_log import HabitLog

from app.habits.intelligence import habit_streak, weekly_performance
from app.habits.intelligence import habit_expense_correlation


async def create_habit(
    db: AsyncSession,
    user_id: int,
    name: str,
) -> Habit:
    habit = Habit(
        user_id=user_id,
        name=name,
        is_active=True,
    )
    db.add(habit)
    await db.commit()
    await db.refresh(habit)
    return habit


async def complete_habit_for_today(
    db: AsyncSession,
    user_id: int,
    habit_id: int,
) -> HabitLog:
    result = await db.execute(
        select(Habit).where(
            Habit.id == habit_id,
            Habit.user_id == user_id,
            Habit.is_active.is_(True),
        )
    )
    habit = result.scalar_one()

    today = date.today()

    result = await db.execute(
        select(HabitLog).where(
            HabitLog.habit_id == habit.id,
            HabitLog.date == today,
        )
    )
    log = result.scalar_one_or_none()

    if log:
        return log

    log = HabitLog(
        habit_id=habit.id,
        date=today,
        completed=True,
    )

    db.add(log)
    await db.commit()
    await db.refresh(log)
    return log


async def habit_insights(
    db: AsyncSession,
    user_id: int,
    habit_id: int,
):
    # enforce ownership
    await db.execute(
        select(Habit.id).where(
            Habit.id == habit_id,
            Habit.user_id == user_id,
            Habit.is_active.is_(True),
        )
    )

    streak = await habit_streak(db, habit_id)
    weekly = await weekly_performance(db, habit_id)

    momentum = "improving" if weekly["score"] >= 70 else "declining"

    return {
        "streak": streak,
        "weekly": weekly,
        "momentum": momentum,
    }


async def habit_financial_impact(
    db: AsyncSession,
    habit_id: int,
    user_id: int,
):
    return await habit_expense_correlation(db, habit_id, user_id)


async def patch_habit_log(
    db: AsyncSession,
    user_id: int,
    habit_id: int,
    data,
):
    result = await db.execute(
        select(Habit).where(
            Habit.id == habit_id,
            Habit.user_id == user_id,
            Habit.is_active.is_(True),
        )
    )
    habit = result.scalar_one()

    log_date = data.date or date.today()

    result = await db.execute(
        select(HabitLog).where(
            HabitLog.habit_id == habit.id,
            HabitLog.date == log_date,
        )
    )
    log = result.scalar_one_or_none()

    if log:
        if data.completed is not None:
            log.completed = data.completed
    else:
        log = HabitLog(
            habit_id=habit.id,
            date=log_date,
            completed=data.completed if data.completed is not None else False,
        )
        db.add(log)

    await db.commit()
    await db.refresh(log)
    return log


async def list_habits(
    db: AsyncSession,
    user_id: int,
):
    result = await db.execute(
        select(Habit)
        .where(
            Habit.user_id == user_id,
            Habit.is_active.is_(True),
        )
        .order_by(Habit.id.desc())
    )
    return result.scalars().all()


async def delete_habit(
    db: AsyncSession,
    user_id: int,
    habit_id: int,
):
    result = await db.execute(
        select(Habit).where(
            Habit.id == habit_id,
            Habit.user_id == user_id,
            Habit.is_active.is_(True),
        )
    )
    habit = result.scalar_one()

    habit.is_active = False
    await db.commit()