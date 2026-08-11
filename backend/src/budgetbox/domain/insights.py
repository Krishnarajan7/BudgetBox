"""Month-story math (port of story_page.dart's _MonthFacts): the monthly recap —
five fixed pages, three conditional ones, ending in a Sankey — plus the journal's
mood-against-money whisper. Pure computation over plain facts."""

import datetime as dt
import math
from collections import defaultdict
from dataclasses import dataclass

from budgetbox.core.money import Paise
from budgetbox.domain.pace import round_half_away_from_zero


@dataclass(frozen=True, slots=True)
class TxnFact:
    amount_paise: Paise
    kind: str  # "expense" | "income" (transfers never enter the story)
    category_name: str | None
    day: dt.date


@dataclass(frozen=True, slots=True)
class Flow:
    name: str
    paise: Paise
    is_income: bool


@dataclass(frozen=True, slots=True)
class QuietWeek:
    """The lightest *complete* week of the month. A week still being lived is never
    judged, so this needs at least two finished weeks to say anything."""

    start_day: int
    end_day: int
    spent_paise: Paise
    projected_paise: Paise  # that week's spend held for a whole month


@dataclass(frozen=True, slots=True)
class MonthStory:
    spent_paise: Paise
    income_paise: Paise
    kept_paise: Paise
    top_category: tuple[str, Paise] | None  # biggest expense category
    biggest_day: tuple[dt.date, Paise] | None
    quiet_days: int  # elapsed days with no spending at all
    flows: list[Flow]  # income sources in, categories out, Kept last
    quietest_week: QuietWeek | None  # only when a quiet week would beat the month


def month_story(
    facts: list[TxnFact], *, window_start: dt.date, window_end: dt.date, today: dt.date
) -> MonthStory:
    spent = sum(f.amount_paise for f in facts if f.kind == "expense")
    income = sum(f.amount_paise for f in facts if f.kind == "income")
    kept = income - spent

    by_category: dict[str, Paise] = defaultdict(int)
    by_income_source: dict[str, Paise] = defaultdict(int)
    by_day: dict[dt.date, Paise] = defaultdict(int)
    for f in facts:
        if f.kind == "expense":
            by_category[f.category_name or "Uncategorised"] += f.amount_paise
            by_day[f.day] += f.amount_paise
        else:
            by_income_source[f.category_name or "Other income"] += f.amount_paise

    top_category = max(by_category.items(), key=lambda kv: kv[1], default=None)
    biggest_day = max(by_day.items(), key=lambda kv: kv[1], default=None)

    last_counted = min(today, window_end - dt.timedelta(days=1))
    quiet_days = 0
    day = window_start
    while day <= last_counted:
        if by_day.get(day, 0) == 0:
            quiet_days += 1
        day += dt.timedelta(days=1)
    quiet_days = max(quiet_days, 0)

    flows = [
        Flow(name=name, paise=paise, is_income=True)
        for name, paise in sorted(by_income_source.items(), key=lambda kv: -kv[1])
    ] + [
        Flow(name=name, paise=paise, is_income=False)
        for name, paise in sorted(by_category.items(), key=lambda kv: -kv[1])
    ]
    if kept > 0:
        flows.append(Flow(name="Kept", paise=kept, is_income=False))

    days_in_window = (window_end - window_start).days
    by_day_of_month = {d.day: paise for d, paise in by_day.items()}
    quiet_week = quietest_week(
        by_day_of_month,
        days_in_month=days_in_window,
        today_day=(today.day if window_start <= today < window_end else days_in_window + 1),
    )
    if quiet_week is not None and quiet_week.projected_paise >= spent:
        quiet_week = None  # a quiet week that wouldn't have saved anything isn't a page

    return MonthStory(
        spent_paise=spent,
        income_paise=income,
        kept_paise=kept,
        top_category=top_category,
        biggest_day=biggest_day,
        quiet_days=quiet_days,
        flows=flows,
        quietest_week=quiet_week,
    )


def quietest_week(
    by_day_of_month: dict[int, Paise], *, days_in_month: int, today_day: int
) -> QuietWeek | None:
    """The lightest whole 7-day block starting on day 1, 8, 15 or 22. A block that
    runs off the end of the month, or whose last day has not been fully lived, ends
    the search — an unfinished week must never win by being short. Ties go earlier.

    Needs at least two finished weeks to compare. With only one, the quietest week
    is simply the only week there is, and calling it quiet says nothing.
    """
    best: tuple[int, int, Paise] | None = None
    finished = 0
    start = 1
    while start + 6 <= days_in_month:
        end = start + 6
        if end >= today_day:
            break
        finished += 1
        total = sum(by_day_of_month.get(day, 0) for day in range(start, end + 1))
        if best is None or total < best[2]:
            best = (start, end, total)
        start += 7
    if best is None or finished < 2 or best[2] <= 0:
        return None
    weeks = max(round_half_away_from_zero(days_in_month / 7), 1)
    return QuietWeek(
        start_day=best[0], end_day=best[1], spent_paise=best[2], projected_paise=best[2] * weeks
    )


# --- conditional story pages --------------------------------------------------


@dataclass(frozen=True, slots=True)
class BudgetHoldCandidate:
    budget_id: str
    name: str
    limit_paise: Paise
    spent_paise: Paise


@dataclass(frozen=True, slots=True)
class BudgetHeld:
    budget_id: str
    name: str
    limit_paise: Paise
    spent_paise: Paise
    spare_paise: Paise
    spare_year_paise: Paise  # that spare, twelve months running
    usage: float


def held_budget(
    candidates: list[BudgetHoldCandidate], *, min_usage: float = 0.5
) -> BudgetHeld | None:
    """The budget that held its line most convincingly: real spending, under the
    limit, and at least half the line used — a barely-touched budget held nothing.
    Ties go to the first candidate, matching the app's strict `>`."""
    best: tuple[BudgetHoldCandidate, float] | None = None
    for c in candidates:
        if c.limit_paise <= 0 or c.spent_paise <= 0 or c.spent_paise > c.limit_paise:
            continue
        usage = c.spent_paise / c.limit_paise
        if usage < min_usage:
            continue
        if best is None or usage > best[1]:
            best = (c, usage)
    if best is None:
        return None
    winner, usage = best
    spare = winner.limit_paise - winner.spent_paise
    return BudgetHeld(
        budget_id=winner.budget_id,
        name=winner.name,
        limit_paise=winner.limit_paise,
        spent_paise=winner.spent_paise,
        spare_paise=spare,
        spare_year_paise=spare * 12,
        usage=usage,
    )


@dataclass(frozen=True, slots=True)
class GoalMoveCandidate:
    goal_id: str
    name: str
    moved_paise: Paise  # contributed inside the window
    done_paise: Paise  # contributed all-time
    target_paise: Paise


@dataclass(frozen=True, slots=True)
class GoalMoved:
    goal_id: str
    name: str
    moved_paise: Paise
    reached: bool
    remaining_paise: Paise
    months_left: int | None  # at this month's rate; None once reached


def moved_goal(candidates: list[GoalMoveCandidate], *, min_share: float = 0.05) -> GoalMoved | None:
    """The goal that actually moved this month: reached, or moved at least a
    twentieth of its target. Biggest mover wins; ties go to the first."""
    best: GoalMoveCandidate | None = None
    for c in candidates:
        if c.moved_paise <= 0 or c.target_paise <= 0:
            continue
        reached = c.done_paise >= c.target_paise
        if not reached and c.moved_paise < c.target_paise * min_share:
            continue
        if best is None or c.moved_paise > best.moved_paise:
            best = c
    if best is None:
        return None
    reached = best.done_paise >= best.target_paise
    remaining = max(best.target_paise - best.done_paise, 0)
    return GoalMoved(
        goal_id=best.goal_id,
        name=best.name,
        moved_paise=best.moved_paise,
        reached=reached,
        remaining_paise=remaining,
        months_left=None if reached else math.ceil(remaining / best.moved_paise),
    )


# --- journal: mood against money ----------------------------------------------


@dataclass(frozen=True, slots=True)
class MoodMoney:
    rough_days: int
    bright_days: int
    rough_avg_paise: Paise
    bright_avg_paise: Paise
    verdict: str  # "rough_costs_more" | "bright_costs_more"


def mood_money(
    pairs: list[tuple[int, Paise]], *, min_days: int = 3, ratio: float = 1.2
) -> MoodMoney | None:
    """Whether rough days (mood 1-2) or bright ones (mood 4-5) cost more. Needs at
    least three of each, and a fifth of difference — below that the book stays quiet
    rather than inventing a pattern. Mood 3 is neither and never counts."""
    rough = [paise for mood, paise in pairs if mood <= 2]
    bright = [paise for mood, paise in pairs if mood >= 4]
    if len(rough) < min_days or len(bright) < min_days:
        return None
    rough_avg = sum(rough) // len(rough)
    bright_avg = sum(bright) // len(bright)
    if rough_avg > bright_avg * ratio:
        verdict = "rough_costs_more"
    elif bright_avg > rough_avg * ratio:
        verdict = "bright_costs_more"
    else:
        return None
    return MoodMoney(
        rough_days=len(rough),
        bright_days=len(bright),
        rough_avg_paise=rough_avg,
        bright_avg_paise=bright_avg,
        verdict=verdict,
    )


# --- streaks ------------------------------------------------------------------


def streak_days(days: set[dt.date], today: dt.date) -> int:
    """Consecutive days ending today (or yesterday, when today isn't written yet).
    A gap ends it; an unwritten today is grace, not a break."""
    cursor = today if today in days else today - dt.timedelta(days=1)
    count = 0
    while cursor in days:
        count += 1
        cursor -= dt.timedelta(days=1)
    return count
