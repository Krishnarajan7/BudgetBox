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
