"""Budget pace/forecast math. Verbatim port of lib/data/repos/budget_math.dart —
color encodes the future: on-pace / projected-over / already-over, plus `pending`
for an expected bill that hasn't landed. Any change here must land in both codebases."""

import math
from dataclasses import dataclass
from enum import StrEnum

from budgetbox.core.money import Paise


class BudgetStatus(StrEnum):
    ON_PACE = "on_pace"
    PROJECTED_OVER = "projected_over"
    OVER = "over"
    PENDING = "pending"


def round_half_away_from_zero(x: float) -> int:
    """Dart's .round(). Python's round() banker's-rounds; that parity gap is a real bug."""
    return math.floor(x + 0.5) if x >= 0 else math.ceil(x - 0.5)


@dataclass(frozen=True, slots=True)
class BudgetPace:
    spent_paise: Paise
    limit_paise: Paise
    elapsed_days: int
    total_days: int
    upcoming_paise: Paise = 0
    """Committed-but-unposted recurring charges inside this period."""

    @property
    def remaining_paise(self) -> Paise:
        return self.limit_paise - self.spent_paise

    @property
    def fraction_spent(self) -> float:
        if self.limit_paise <= 0:
            return 1.0
        return self.spent_paise / self.limit_paise

    @property
    def fraction_elapsed(self) -> float:
        if self.total_days <= 0:
            return 1.0
        return min(max(self.elapsed_days / self.total_days, 0.0), 1.0)

    @property
    def projected_paise(self) -> Paise:
        """Straight-line projection of where the period ends at today's run rate,
        with committed upcoming charges counted in full."""
        if self.elapsed_days <= 0:
            return self.spent_paise + self.upcoming_paise
        run_rate = self.spent_paise / self.elapsed_days
        return round_half_away_from_zero(run_rate * self.total_days) + self.upcoming_paise

    @property
    def status(self) -> BudgetStatus:
        if self.spent_paise > self.limit_paise:
            return BudgetStatus.OVER
        if self.spent_paise == 0 and self.upcoming_paise > 0:
            return BudgetStatus.PENDING
        if self.projected_paise > self.limit_paise:
            return BudgetStatus.PROJECTED_OVER
        return BudgetStatus.ON_PACE

    @property
    def projected_overspend_paise(self) -> Paise:
        """How far past the line the projection runs (0 when on pace)."""
        return max(self.projected_paise - self.limit_paise, 0)
