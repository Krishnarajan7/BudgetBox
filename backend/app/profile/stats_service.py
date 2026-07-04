from sqlalchemy import select, func
from decimal import Decimal

from app.models.task import Task
from app.models.task_log import TaskLog
from app.models.habit import Habit
from app.models.habit_log import HabitLog
from app.models.transaction import Transaction, TransactionType
from app.models.budget import Budget
from app.models.category import Category
from app.models.food_log import FoodLog
from app.models.food_nutrient_profile import FoodNutrientProfile

from app.streaks.service import calculate_streak
from app.achievements.service import evaluate_achievements
from app.achievements.definitions import ACHIEVEMENTS


async def profile_stats(db, user_id: int):
    task_streak = await calculate_streak(
        db,
        date_column=TaskLog.completed_at,
        user_filter=Task.user_id == user_id,
    )

    habit_streak = await calculate_streak(
        db,
        date_column=HabitLog.date,
        user_filter=Habit.user_id == user_id,
    )

    total_tasks_completed = await db.scalar(
        select(func.count(TaskLog.id))
        .join(Task, Task.id == TaskLog.task_id)
        .where(Task.user_id == user_id)
    ) or 0

    total_habits_completed = await db.scalar(
        select(func.count(HabitLog.id))
        .join(Habit, Habit.id == HabitLog.habit_id)
        .where(Habit.user_id == user_id)
    ) or 0

    total_expenses = await db.scalar(
        select(func.coalesce(func.sum(Transaction.amount), 0))
        .where(
            Transaction.user_id == user_id,
            Transaction.type == TransactionType.EXPENSE,
        )
    ) or Decimal("0")

    total_income = await db.scalar(
        select(func.coalesce(func.sum(Transaction.amount), 0))
        .where(
            Transaction.user_id == user_id,
            Transaction.type == TransactionType.INCOME,
        )
    ) or Decimal("0")

    total_budgets = await db.scalar(
        select(func.count(Budget.id))
        .where(Budget.user_id == user_id)
    ) or 0

    total_categories = await db.scalar(
        select(func.count(Category.id))
        .where(Category.user_id == user_id)
    ) or 0

    total_food_logs = await db.scalar(
        select(func.count(FoodLog.id))
        .where(FoodLog.user_id == user_id)
    ) or 0

    total_nutrient_profiles = await db.scalar(
        select(func.count(FoodNutrientProfile.id))
    ) or 0

    stats = {
        "task_streak": task_streak,
        "habit_streak": habit_streak,
        "total_tasks_completed": total_tasks_completed,
        "total_habits_completed": total_habits_completed,
        "total_expenses": Decimal(total_expenses),
        "total_income": Decimal(total_income),
        "total_budgets": total_budgets,
        "total_categories": total_categories,
        "total_food_logs": total_food_logs,
        "total_nutrient_profiles": total_nutrient_profiles,
    }

    unlocked_achievements = evaluate_achievements(stats)

    return {
        **stats,
        "achievements_unlocked": len(unlocked_achievements),
        "total_achievements": len(ACHIEVEMENTS),
    }
