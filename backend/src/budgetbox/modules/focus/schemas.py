from datetime import date, datetime
from typing import Annotated

from pydantic import Field

from budgetbox.api.schemas import APIModel, Instant
from budgetbox.modules.focus.models import FocusKind

# Strict like money: a sitting is a whole number of minutes, capped at ten hours.
Minutes = Annotated[int, Field(strict=True, gt=0, le=600)]
Label = Annotated[str | None, Field(max_length=60)]


class FocusIn(APIModel):
    started_at: Instant
    minutes: Minutes
    kind: FocusKind
    # Minutes are what was truly sat, so an abandoned sitting is still a line.
    completed: bool = False
    label: Label = None


class FocusPatch(APIModel):
    minutes: Minutes | None = None
    completed: bool | None = None
    label: Label = None


class FocusOut(APIModel):
    id: str
    started_at: datetime
    minutes: int
    kind: FocusKind
    completed: bool
    label: str | None
    created_at: datetime
    updated_at: datetime


class StatsOut(APIModel):
    total_minutes: int
    sessions: int
    best_day: date | None
    best_day_minutes: int
