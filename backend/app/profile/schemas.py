from pydantic import BaseModel
from datetime import date


class ProfileResponse(BaseModel):
    first_name: str
    last_name: str
    email: str
    phone: str | None
    location: str | None
    occupation: str | None
    website: str | None
    bio: str | None
    timezone: str
    avatar_url: str | None
    join_date: date


class ProfileUpdate(BaseModel):
    first_name: str | None = None
    last_name: str | None = None
    phone: str | None = None
    location: str | None = None
    occupation: str | None = None
    website: str | None = None
    bio: str | None = None
    timezone: str | None = None
    avatar_url: str | None = None


class StreakStats(BaseModel):
    current_streak: int
    longest_streak: int
    active_days: int
    


class ProfileStatsResponse(BaseModel):
    task_streak: StreakStats
    habit_streak: StreakStats
    total_tasks_completed: int
    total_habits_completed: int
    total_expenses: float
    total_income: float
    total_budgets: int
    total_categories: int
    total_food_logs: int
    total_nutrient_profiles: int
    achievements_unlocked: int
    total_achievements: int
    
