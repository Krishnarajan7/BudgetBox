from datetime import date
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Mood
# ---------------------------------------------------------------------------


class MoodUpsert(BaseModel):
    mood: int = Field(ge=1, le=5)
    note: Optional[str] = None


class MoodResponse(BaseModel):
    id: int
    date: date
    mood: int
    note: Optional[str]

    model_config = {"from_attributes": True}


# ---------------------------------------------------------------------------
# Water
# ---------------------------------------------------------------------------


class WaterUpsert(BaseModel):
    glasses: int = Field(ge=0)
    goal: Optional[int] = Field(default=None, ge=1)


class WaterResponse(BaseModel):
    id: int
    date: date
    glasses: int
    goal: int

    model_config = {"from_attributes": True}


# ---------------------------------------------------------------------------
# Sleep
# ---------------------------------------------------------------------------


class SleepUpsert(BaseModel):
    hours: Decimal = Field(ge=0, le=24)
    quality: Optional[int] = Field(default=None, ge=1, le=5)
    bedtime: Optional[str] = Field(default=None, max_length=5)
    wake_time: Optional[str] = Field(default=None, max_length=5)


class SleepResponse(BaseModel):
    id: int
    date: date
    hours: Decimal
    quality: Optional[int]
    bedtime: Optional[str]
    wake_time: Optional[str]

    model_config = {"from_attributes": True}
