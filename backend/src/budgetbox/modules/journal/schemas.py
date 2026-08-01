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
