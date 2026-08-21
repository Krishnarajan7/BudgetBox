from datetime import date, datetime
from typing import Annotated

from pydantic import Field

from budgetbox.api.schemas import APIModel, Instant

# A kind is a key, not a sentence: short, and stored exactly as the app spells it.
Kind = Annotated[str, Field(strict=True, min_length=1, max_length=32)]
# What was eaten, or why the mark exists. A note, never an essay.
Note = Annotated[str | None, Field(max_length=280)]


class MarkIn(APIModel):
    date: date
    kind: Kind
    note: Note = None
    at: Instant


class MarkOut(APIModel):
    id: str
    date: date
    kind: str
    note: str | None
    at: datetime
    created_at: datetime
    updated_at: datetime
