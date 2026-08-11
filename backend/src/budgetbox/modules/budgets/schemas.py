from datetime import date, datetime

from pydantic import Field

from budgetbox.api.schemas import APIModel, PositivePaise, StrictPaise
from budgetbox.domain.pace import BudgetStatus
from budgetbox.modules.budgets.models import BudgetKind, BudgetPeriod
from budgetbox.modules.categories.schemas import CategoryOut


class BudgetIn(APIModel):
    name: str = Field(min_length=1, max_length=60)
    category_id: str | None = None
    limit_paise: PositivePaise
    period: BudgetPeriod
    kind: BudgetKind = BudgetKind.ALL
    rollover: bool = False


class BudgetPatch(APIModel):
    name: str | None = Field(default=None, min_length=1, max_length=60)
    limit_paise: PositivePaise | None = None
    rollover: bool | None = None
    archived: bool | None = None


class BudgetOut(APIModel):
    id: str
    category_id: str | None
    name: str
    limit_paise: PositivePaise
    period: BudgetPeriod
    kind: BudgetKind
    rollover: bool
    archived: bool
    created_at: datetime
    updated_at: datetime


class PaceOut(APIModel):
    spent_paise: StrictPaise
    limit_paise: StrictPaise  # effective limit (rollover applied)
    elapsed_days: int
    total_days: int
    upcoming_paise: StrictPaise
    remaining_paise: StrictPaise
    fraction_spent: float
    fraction_elapsed: float
    projected_paise: StrictPaise
    status: BudgetStatus
    projected_overspend_paise: StrictPaise


class BudgetView(APIModel):
    budget: BudgetOut
    category: CategoryOut | None
    window_start: date | None  # null for custom (trip-book) budgets
    window_end: date | None
    pace: PaceOut


class MonthSpend(APIModel):
    month: str  # 'yyyy-MM'
    spent_paise: StrictPaise
    held: bool  # real spending, and it stayed under the line


class BudgetTrail(APIModel):
    """The evidence behind one budget row: what the last months actually cost (the
    sparkline), whether the line has been held and for how long, and the daily
    cumulative climb against an even pace."""

    budget_id: str
    limit_paise: StrictPaise
    months: list[MonthSpend]  # oldest first, the current month last
    held_months_running: int  # complete months, counting back from the last one
    daily_cumulative_paise: list[StrictPaise]  # day 1 … today, inside the period
    even_pace_paise: list[StrictPaise]  # the same days, spent perfectly evenly


class RebalanceIn(APIModel):
    budget_ids: list[str] = Field(min_length=2, max_length=100)


class BudgetSuggestion(APIModel):
    category_id: str
    suggested_limit_paise: PositivePaise
    average_spent_paise: StrictPaise
    months: int
