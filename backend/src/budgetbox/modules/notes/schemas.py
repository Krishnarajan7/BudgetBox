from datetime import datetime

from pydantic import Field

from budgetbox.api.schemas import APIModel


class NoteIn(APIModel):
    title: str = Field(default="", max_length=200)
    body: str = ""
    pinned: bool = False


class NotePatch(APIModel):
    title: str | None = Field(default=None, max_length=200)
    body: str | None = None
    pinned: bool | None = None
    archived: bool | None = None


class NoteOut(APIModel):
    id: str
    title: str
    body: str
    pinned: bool
    archived: bool
    created_at: datetime
    updated_at: datetime
