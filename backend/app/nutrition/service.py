from datetime import date, timedelta
from collections import defaultdict
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.food_log import FoodLog
from app.models.food_nutrient_profile import FoodNutrientProfile
from app.nutrition.intelligence import generate_health_report


async def _daily_nutrient_intake(
    db: AsyncSession,
    user_id: int,
    target_date: date,
) -> dict:
    result = await db.execute(
        select(FoodLog, FoodNutrientProfile)
        .join(
            FoodNutrientProfile,
            FoodLog.food_id == FoodNutrientProfile.id,
        )
        .where(
            FoodLog.user_id == user_id,
            FoodLog.consumed_at == target_date,
        )
    )

    totals = defaultdict(float)

    for log, food in result.all():
        factor = log.quantity_g / 100.0

        totals["calories_kcal"] += food.calories_kcal * factor
        totals["protein_g"] += food.protein_g * factor
        totals["carbs_g"] += food.carbs_g * factor
        totals["fat_g"] += food.fat_g * factor
        totals["fiber_g"] += food.fiber_g * factor

        totals["vitamin_a_mcg"] += food.vitamin_a_mcg * factor
        totals["vitamin_c_mg"] += food.vitamin_c_mg * factor
        totals["vitamin_d_mcg"] += food.vitamin_d_mcg * factor

        totals["iron_mg"] += food.iron_mg * factor
        totals["calcium_mg"] += food.calcium_mg * factor
        totals["potassium_mg"] += food.potassium_mg * factor

    return {k: round(v, 2) for k, v in totals.items()}


async def daily_health_report(
    db: AsyncSession,
    user_id: int,
    target_date: date,
) -> dict:
    intake = await _daily_nutrient_intake(db, user_id, target_date)

    return {
        "date": target_date,
        "report": generate_health_report(intake),
    }


async def weekly_health_report(
    db: AsyncSession,
    user_id: int,
    end_date: date,
) -> dict:
    totals = defaultdict(float)

    for i in range(7):
        day = end_date - timedelta(days=i)
        daily = await _daily_nutrient_intake(db, user_id, day)

        for k, v in daily.items():
            totals[k] += v

    averaged = {k: round(v / 7, 2) for k, v in totals.items()}

    return {
        "start_date": end_date - timedelta(days=6),
        "end_date": end_date,
        "report": generate_health_report(averaged),
    }
