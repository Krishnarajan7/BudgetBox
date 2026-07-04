from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update
from datetime import date

from app.models.habit import Habit
from app.models.habit_log import HabitLog
from app.core.errors import AppError

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
    result = await db.execute(
        select(Habit.id).where(
            Habit.id == habit_id,
            Habit.user_id == user_id,
            Habit.is_active.is_(True),
        )
    )
    if result.scalar_one_or_none() is None:
        raise AppError("HABIT_NOT_FOUND", "Habit not found", 404)

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
    # enforce ownership
    result = await db.execute(
        select(Habit.id).where(
            Habit.id == habit_id,
            Habit.user_id == user_id,
            Habit.is_active.is_(True),
        )
    )
    if result.scalar_one_or_none() is None:
        raise AppError("HABIT_NOT_FOUND", "Habit not found", 404)

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
    habit = result.scalar_one_or_none()
    if habit is None:
        raise AppError("HABIT_NOT_FOUND", "Habit not found", 404)

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


async def get_habit_log_today(
    db: AsyncSession,
    user_id: int,
    habit_id: int,
):
    # enforce ownership
    result = await db.execute(
        select(Habit.id).where(
            Habit.id == habit_id,
            Habit.user_id == user_id,
            Habit.is_active.is_(True),
        )
    )
    if result.scalar_one_or_none() is None:
        raise AppError("HABIT_NOT_FOUND", "Habit not found", 404)

    # same "today" definition as patch_habit_log's default (data.date or date.today())
    today = date.today()

    result = await db.execute(
        select(HabitLog).where(
            HabitLog.habit_id == habit_id,
            HabitLog.date == today,
        )
    )
    log = result.scalar_one_or_none()

    return {
        "habit_id": habit_id,
        "date": today,
        "completed": log.completed if log is not None else False,
    }


async def update_habit(
    db: AsyncSession,
    user_id: int,
    habit_id: int,
    data,
) -> Habit:
    result = await db.execute(
        select(Habit).where(
            Habit.id == habit_id,
            Habit.user_id == user_id,
            Habit.is_active.is_(True),
        )
    )
    habit = result.scalar_one_or_none()
    if habit is None:
        raise AppError("HABIT_NOT_FOUND", "Habit not found", 404)

    if data.name is not None:
        habit.name = data.name
    if data.is_active is not None:
        habit.is_active = data.is_active

    await db.commit()
    await db.refresh(habit)
    return habit


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