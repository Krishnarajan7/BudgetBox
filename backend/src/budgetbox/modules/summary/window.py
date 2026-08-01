from dataclasses import dataclass
from datetime import date, timedelta

from budgetbox.domain.periods import salary_month_window


@dataclass(frozen=True, slots=True)
class WindowState:
    start: date
    end: date
    elapsed_days: int  # days fully or partly lived, today included
    total_days: int
    tomorrow: date


def salary_window_state(today: date, salary_day: int) -> WindowState:
    start, end = salary_month_window(today, salary_day)
    return WindowState(
        start=start,
        end=end,
        elapsed_days=(today - start).days + 1,
        total_days=(end - start).days,
        tomorrow=today + timedelta(days=1),
    )
