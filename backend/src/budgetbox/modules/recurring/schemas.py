from datetime import date, datetime

from pydantic import Field

from budgetbox.api.schemas import APIModel, PositivePaise, StrictPaise
from budgetbox.modules.recurring.models import RecurringKind


class RecurringIn(APIModel):
    title: str = Field(min_length=1, max_length=120)
    amount_paise: PositivePaise
    account_id: str
    category_id: str | None = None
    kind: RecurringKind
    every_months: int = Field(default=1, ge=1, le=60)
    day_of_month: int = Field(ge=1, le=31)
    # Omitted: first due is the next matching day (today counts).
    next_due: date | None = None
    active: bool = True


class RecurringPatch(APIModel):
    title: str | None = Field(default=None, min_length=1, max_length=120)
    amount_paise: PositivePaise | None = None
    account_id: str | None = None
    category_id: str | None = None
    every_months: int | None = Field(default=None, ge=1, le=60)
    day_of_month: int | None = Field(default=None, ge=1, le=31)
    next_due: date | None = None
    active: bool | None = None


class RecurringOut(APIModel):
    id: str
    title: str
    amount_paise: PositivePaise
    account_id: str
    category_id: str | None
    kind: RecurringKind
    every_months: int
    day_of_month: int
    next_due: date
    active: bool
    last_materialized_due: date | None
    created_at: datetime
    updated_at: datetime


class DueItem(APIModel):
    recurring: RecurringOut
    due: date
    is_bill: bool


class UpcomingOut(APIModel):
    items: list[DueItem]
    # Committed spend hero: every active recurring normalized to a per-month figure
    # (yearly plans counted at 1/12 a month).
    committed_monthly_paise: StrictPaise
