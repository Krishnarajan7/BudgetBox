from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from datetime import date, timedelta

from app.models.habit_log import HabitLog
from app.models.transaction import Transaction, TransactionType

async def habit_streak(db: AsyncSession, habit_id: int):
    result = await db.execute(
        select(HabitLog)
        .where(
            HabitLog.habit_id == habit_id,
            HabitLog.completed == True,
        )
        .order_by(HabitLog.date.desc())
    )
    logs = result.scalars().all()

    if not logs:
        return {
            "current_streak": 0,
            "best_streak": 0,
            "consistency": 0,
        }

    current_streak = 0
    best_streak = 0
    streak = 0
    previous_date = None

    for log in logs:
        if previous_date is None:
            streak = 1
        else:
            if previous_date - log.date == timedelta(days=1):
                streak += 1
            else:
                streak = 1

        best_streak = max(best_streak, streak)
        previous_date = log.date

    today = date.today()
    if logs[0].date == today or logs[0].date == today - timedelta(days=1):
        current_streak = streak
    else:
        current_streak = 0

    total_days = (today - logs[-1].date).days + 1
    consistency = round((len(logs) / total_days) * 100, 2)

    return {
        "current_streak": current_streak,
        "best_streak": best_streak,
        "consistency": consistency,
    }

async def weekly_performance(db: AsyncSession, habit_id: int):
    today = date.today()
    start = today - timedelta(days=6)

    result = await db.execute(
        select(HabitLog)
        .where(
            HabitLog.habit_id == habit_id,
            HabitLog.date.between(start, today),
            HabitLog.completed == True,
        )
    )

    completed_days = len(result.scalars().all())

    return {
        "completed_days": completed_days,
        "missed_days": 7 - completed_days,
        "score": round((completed_days / 7) * 100, 2),
    }


async def habit_expense_correlation(
    db,
    habit_id: int,
    user_id: int,
):
    habit_days_result = await db.execute(
        select(HabitLog.date)
        .where(
            HabitLog.habit_id == habit_id,
            HabitLog.completed == True,
        )
    )
    habit_days = {row[0] for row in habit_days_result.all()}

    if not habit_days:
        return {
            "correlation": "insufficient_data",
            "message": "Not enough habit data to analyze",
        }

    expense_result = await db.execute(
        select(
            Transaction.occurred_at,
            func.sum(Transaction.amount)
        )
        .where(
            Transaction.user_id == user_id,
            Transaction.type == TransactionType.EXPENSE,
        )
        .group_by(Transaction.occurred_at)
    )

    with_habit = []
    without_habit = []

    for occurred_at, total in expense_result.all():
        day = occurred_at.date()
        if day in habit_days:
            with_habit.append(float(total))
        else:
            without_habit.append(float(total))

    if not with_habit or not without_habit:
        return {
            "correlation": "insufficient_data",
            "message": "Not enough comparative expense data",
        }

    avg_with = sum(with_habit) / len(with_habit)
    avg_without = sum(without_habit) / len(without_habit)

    impact = avg_without - avg_with

    return {
        "average_spend_on_habit_days": round(avg_with, 2),
        "average_spend_on_non_habit_days": round(avg_without, 2),
        "difference": round(impact, 2),
        "insight": (
            "You spend less on days you complete this habit"
            if impact > 0
            else "This habit does not reduce spending"
        ),
    }
