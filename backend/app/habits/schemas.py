from pydantic import BaseModel
from datetime import date


class HabitCreate(BaseModel):
    name: str


class HabitResponse(BaseModel):
    id: int
    name: str
    is_active: bool


class HabitLogResponse(BaseModel):
    habit_id: int
    date: date
    completed: bool
