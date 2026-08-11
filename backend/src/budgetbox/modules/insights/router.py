"""The swipeable monthly story: hero numbers, top category, biggest day, quiet
days, Sankey flows, and the verdict against last month."""

import datetime as dt

from fastapi import APIRouter

from budgetbox.api.deps import SessionDep
from budgetbox.api.params import parse_month
from budgetbox.api.schemas import APIModel, StrictPaise
from budgetbox.core.time import today_ist
from budgetbox.domain.insights import BudgetHeld, GoalMoved, MonthStory
from budgetbox.domain.periods import add_months, month_end_exclusive, month_start
from budgetbox.modules.insights import service

router = APIRouter(prefix="/insights", tags=["insights"])


class FlowOut(APIModel):
    name: str
    paise: StrictPaise
    is_income: bool


class NamedAmount(APIModel):
    name: str
    paise: StrictPaise


class DayAmount(APIModel):
    date: dt.date
    paise: StrictPaise


class VsLastMonth(APIModel):
    spent_delta_paise: StrictPaise  # positive = spent more than last month
    verdict: str  # "less" | "more" | "same"


class QuietWeekOut(APIModel):
    """Only present when the month had a quiet week worth pointing at."""

    start_day: int
    end_day: int
    spent_paise: StrictPaise
    projected_paise: StrictPaise  # that week, held for a whole month


class BudgetHeldOut(APIModel):
    budget_id: str
    name: str
    limit_paise: StrictPaise
    spent_paise: StrictPaise
    spare_paise: StrictPaise
    spare_year_paise: StrictPaise
    usage: float


class GoalMovedOut(APIModel):
    goal_id: str
    name: str
    moved_paise: StrictPaise
    reached: bool
    remaining_paise: StrictPaise
    months_left: int | None


class MonthStoryOut(APIModel):
    month: str
    label: str
    spent_paise: StrictPaise
    income_paise: StrictPaise
    kept_paise: StrictPaise
    top_category: NamedAmount | None
    biggest_day: DayAmount | None
    quiet_days: int
    flows: list[FlowOut]
    vs_last_month: VsLastMonth
    # Conditional pages: null means the month didn't earn that page.
    quietest_week: QuietWeekOut | None
    budget_held: BudgetHeldOut | None
    goal_moved: GoalMovedOut | None


def _out(
    month_first: dt.date,
    story: MonthStory,
    prev: MonthStory,
    *,
    budget_held: BudgetHeld | None,
    goal_moved: GoalMoved | None,
) -> MonthStoryOut:
    delta = story.spent_paise - prev.spent_paise
    verdict = "same" if delta == 0 else ("more" if delta > 0 else "less")
    return MonthStoryOut(
        month=f"{month_first.year:04d}-{month_first.month:02d}",
        label=month_first.strftime("%B %Y"),
        spent_paise=story.spent_paise,
        income_paise=story.income_paise,
        kept_paise=story.kept_paise,
        top_category=(
            NamedAmount(name=story.top_category[0], paise=story.top_category[1])
            if story.top_category
            else None
        ),
        biggest_day=(
            DayAmount(date=story.biggest_day[0], paise=story.biggest_day[1])
            if story.biggest_day
            else None
        ),
        quiet_days=story.quiet_days,
        flows=[FlowOut(name=f.name, paise=f.paise, is_income=f.is_income) for f in story.flows],
        vs_last_month=VsLastMonth(spent_delta_paise=delta, verdict=verdict),
        quietest_week=(
            QuietWeekOut(
                start_day=story.quietest_week.start_day,
                end_day=story.quietest_week.end_day,
                spent_paise=story.quietest_week.spent_paise,
                projected_paise=story.quietest_week.projected_paise,
            )
            if story.quietest_week is not None
            else None
        ),
        budget_held=(
            BudgetHeldOut(
                budget_id=budget_held.budget_id,
                name=budget_held.name,
                limit_paise=budget_held.limit_paise,
                spent_paise=budget_held.spent_paise,
                spare_paise=budget_held.spare_paise,
                spare_year_paise=budget_held.spare_year_paise,
                usage=budget_held.usage,
            )
            if budget_held is not None
            else None
        ),
        goal_moved=(
            GoalMovedOut(
                goal_id=goal_moved.goal_id,
                name=goal_moved.name,
                moved_paise=goal_moved.moved_paise,
                reached=goal_moved.reached,
                remaining_paise=goal_moved.remaining_paise,
                months_left=goal_moved.months_left,
            )
            if goal_moved is not None
            else None
        ),
    )


@router.get("/month-story")
def month_story(session: SessionDep, month: str | None = None) -> MonthStoryOut:
    today = today_ist()
    first = parse_month(month) or month_start(today)
    end = month_end_exclusive(first)
    story = service.story_for(session, month_start(first), end, today)
    prev_year, prev_month = add_months(first.year, first.month, -1)
    prev_first = dt.date(prev_year, prev_month, 1)
    prev = service.story_for(session, prev_first, first, today)
    return _out(
        first,
        story,
        prev,
        budget_held=service.budget_that_held(session, first, end),
        goal_moved=service.goal_that_moved(session, first, end),
    )
