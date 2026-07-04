from pydantic import BaseModel
from datetime import date, datetime
from typing import Optional


class NoteCreate(BaseModel):
    title: str
    body: str
    pinned: bool = False


class NoteUpdate(BaseModel):
    title: Optional[str] = None
    body: Optional[str] = None
    pinned: Optional[bool] = None


class NoteResponse(BaseModel):
    id: int
    title: str
    body: str
    pinned: bool
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class JournalEntryUpsert(BaseModel):
    body: str
    mood_note: Optional[str] = None


class JournalEntryResponse(BaseModel):
    id: int
    date: date
    body: str
    mood_note: Optional[str] = None
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}
