from datetime import date, datetime

from pydantic import Field

from budgetbox.api.schemas import APIModel, Instant, PositivePaise, StrictPaise
from budgetbox.modules.goals.models import GoalKind


class GoalIn(APIModel):
    name: str = Field(min_length=1, max_length=60)
    target_paise: PositivePaise
    kind: GoalKind
    target_date: date | None = None
    monthly_paise: PositivePaise | None = None


class GoalPatch(APIModel):
    name: str | None = Field(default=None, min_length=1, max_length=60)
    target_paise: PositivePaise | None = None
    target_date: date | None = None
    monthly_paise: PositivePaise | None = None
    archived: bool | None = None


class GoalOut(APIModel):
    id: str
    name: str
    target_paise: PositivePaise
    kind: GoalKind
    target_date: date | None
    monthly_paise: StrictPaise | None
    archived: bool
    created_at: datetime
    updated_at: datetime


class GoalView(APIModel):
    """Port of GoalView: done/remaining over goal-tagged txns, plus the ETA the
    setup ritual answers back ('at ₹X a month you'd reach this by …')."""

    goal: GoalOut
    done_paise: StrictPaise
    entry_count: int
    remaining_paise: StrictPaise
    fraction: float
    reached: bool
    eta: date | None
    # The last six calendar months, oldest first: did anything go in that month?
    # The rhythm cells on the goals page — showing up beats showing up big.
    rhythm: list[bool]


class ContributeIn(APIModel):
    amount_paise: PositivePaise
    account_id: str
    at: Instant | None = None
    note: str | None = None
