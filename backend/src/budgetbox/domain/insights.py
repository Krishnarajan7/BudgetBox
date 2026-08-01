"""Month-story math (port of story_page.dart's _MonthFacts): the five-page monthly
recap ending in a Sankey. Pure computation over plain txn facts."""

import datetime as dt
from collections import defaultdict
from dataclasses import dataclass

from budgetbox.core.money import Paise


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
class MonthStory:
    spent_paise: Paise
    income_paise: Paise
    kept_paise: Paise
    top_category: tuple[str, Paise] | None  # biggest expense category
    biggest_day: tuple[dt.date, Paise] | None
    quiet_days: int  # elapsed days with no spending at all
    flows: list[Flow]  # income sources in, categories out, Kept last


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

    return MonthStory(
        spent_paise=spent,
        income_paise=income,
        kept_paise=kept,
        top_category=top_category,
        biggest_day=biggest_day,
        quiet_days=quiet_days,
        flows=flows,
    )
