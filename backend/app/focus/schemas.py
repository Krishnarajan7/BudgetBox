from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel, Field

FocusKind = Literal["work", "break"]


class FocusSessionCreate(BaseModel):
    started_at: datetime
    duration_min: int = Field(gt=0)
    kind: FocusKind
    label: Optional[str] = Field(default=None, max_length=255)
    completed: bool


class FocusSessionResponse(BaseModel):
    id: int
    started_at: datetime
    duration_min: int
    kind: FocusKind
    label: Optional[str]
    completed: bool
    created_at: datetime

    model_config = {"from_attributes": True}


class FocusStatsResponse(BaseModel):
    today_minutes: int
    week_minutes: int
    today_sessions: int
    week_sessions: int
    current_streak_days: int
