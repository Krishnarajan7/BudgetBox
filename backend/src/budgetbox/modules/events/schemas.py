import datetime as dt

from pydantic import Field

from budgetbox.api.schemas import APIModel
from budgetbox.modules.events.models import EventRepeat


class EventIn(APIModel):
    title: str = Field(min_length=1, max_length=120)
    note: str | None = None
    # The anchor day. For a yearly repeat this is the first observance.
    date: dt.date
    # Minutes past midnight; null = all-day (sorts first on its day).
    time_minutes: int | None = Field(default=None, ge=0, le=1439)
    # Minute-of-day the owner asked to be nudged at; null = no reminder.
    remind_minutes: int | None = Field(default=None, ge=0, le=1439)
    repeat: EventRepeat = EventRepeat.NONE


class EventPatch(APIModel):
    title: str | None = Field(default=None, min_length=1, max_length=120)
    note: str | None = None
    date: dt.date | None = None
    time_minutes: int | None = Field(default=None, ge=0, le=1439)
    remind_minutes: int | None = Field(default=None, ge=0, le=1439)
    repeat: EventRepeat | None = None
    archived: bool | None = None


class EventOut(APIModel):
    id: str
    title: str
    note: str | None
    date: dt.date
    time_minutes: int | None
    remind_minutes: int | None
    repeat: EventRepeat
    archived: bool
    created_at: dt.datetime
    updated_at: dt.datetime


class OccurrenceOut(APIModel):
    """One concrete observance of an event inside a queried window: the stored row
    plus the resolved calendar date (a yearly event yields one per year)."""

    event: EventOut
    date: dt.date
    time_minutes: int | None
