from datetime import date, datetime

from pydantic import Field

from budgetbox.api.schemas import APIModel


class JournalIn(APIModel):
    """The day itself is the path param, never the payload — one entry per IST day."""

    body: str = Field(default="", max_length=20_000)
    mood: int | None = Field(default=None, ge=1, le=5)  # 1 rough … 5 great


class JournalOut(APIModel):
    date: date
    body: str
    mood: int | None
    created_at: datetime
    updated_at: datetime


class DayFacts(APIModel):
    """What the rest of the box already knows about a day, so the page arrives
    half-written."""

    date: date
    spent_paise: int
    txn_count: int
    focus_minutes: int
    notes_count: int


class MoodMoneyOut(APIModel):
    """Whether rough days or bright ones cost more. Null on the month view when
    there isn't enough to say — the book would rather stay quiet than guess."""

    rough_days: int
    bright_days: int
    rough_avg_paise: int
    bright_avg_paise: int
    verdict: str  # 'rough_costs_more' | 'bright_costs_more'


class JournalMonth(APIModel):
    month: str  # 'yyyy-MM'
    entries: list[JournalOut]  # newest day first
    mood_dots: list[int | None]  # one slot per calendar day of the month
    pages_written: int  # days with words or a mood
    streak_days: int  # consecutive written days ending today (or yesterday)
    mood_money: MoodMoneyOut | None
