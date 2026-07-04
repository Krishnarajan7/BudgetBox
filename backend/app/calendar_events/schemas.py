from datetime import date as date_, datetime
from typing import Literal

from pydantic import BaseModel, Field

EventKind = Literal["event", "birthday", "anniversary", "reminder", "important_date"]

# HH:MM, 00-23 : 00-59
TIME_PATTERN = r"^([01]\d|2[0-3]):[0-5]\d$"


class EventCreate(BaseModel):
    title: str
    date: date_
    time: str | None = Field(default=None, pattern=TIME_PATTERN)
    kind: EventKind = "event"
    note: str | None = None
    recur_yearly: bool = False


class EventUpdate(BaseModel):
    title: str | None = None
    date: date_ | None = None
    time: str | None = Field(default=None, pattern=TIME_PATTERN)
    kind: EventKind | None = None
    note: str | None = None
    recur_yearly: bool | None = None


class EventResponse(BaseModel):
    id: int
    title: str
    date: date_
    time: str | None
    kind: str
    note: str | None
    recur_yearly: bool
    created_at: datetime
    occurs_on: date_
    years_since: int | None = None

    model_config = {"from_attributes": True}


class TaskDueItem(BaseModel):
    id: int
    title: str
    priority: str
    completed: bool


class CalendarDay(BaseModel):
    events: list[EventResponse]
    tasks_due: list[TaskDueItem]


class CalendarResponse(BaseModel):
    days: dict[str, CalendarDay]
