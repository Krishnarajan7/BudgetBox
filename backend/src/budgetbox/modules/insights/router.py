"""The swipeable monthly story: hero numbers, top category, biggest day, quiet
days, Sankey flows, and the verdict against last month."""

import datetime as dt

from fastapi import APIRouter

from budgetbox.api.deps import SessionDep
from budgetbox.api.params import parse_month
from budgetbox.api.schemas import APIModel, StrictPaise
from budgetbox.core.time import today_ist
from budgetbox.domain.insights import MonthStory
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


def _out(month_first: dt.date, story: MonthStory, prev: MonthStory) -> MonthStoryOut:
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
    )


@router.get("/month-story")
def month_story(session: SessionDep, month: str | None = None) -> MonthStoryOut:
    today = today_ist()
    first = parse_month(month) or month_start(today)
    story = service.story_for(session, month_start(first), month_end_exclusive(first), today)
    prev_year, prev_month = add_months(first.year, first.month, -1)
    prev_first = dt.date(prev_year, prev_month, 1)
    prev = service.story_for(session, prev_first, first, today)
    return _out(first, story, prev)
