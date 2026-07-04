from datetime import date
from typing import Optional

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.auth.deps import get_current_user
from app.models.user import User

from app.journal.schemas import (
    NoteCreate,
    NoteUpdate,
    NoteResponse,
    JournalEntryUpsert,
    JournalEntryResponse,
)
from app.journal.service import (
    create_note,
    list_notes,
    update_note,
    delete_note,
    upsert_journal_entry,
    list_journal_entries,
    delete_journal_entry,
    get_day_summary,
)


notes_router = APIRouter(prefix="/notes", tags=["notes"])
journal_router = APIRouter(prefix="/journal", tags=["journal"])

# Combined router exposing both prefixes, so callers that only want a single
# import (`from app.journal.router import router`) can register everything
# in one `app.include_router(router)` call.
router = APIRouter()


# ---------------------------------------------------------------------------
# Notes
# ---------------------------------------------------------------------------


@notes_router.post(
    "",
    response_model=NoteResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_note_endpoint(
    data: NoteCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await create_note(db, user.id, data)


@notes_router.get("", response_model=list[NoteResponse])
async def list_notes_endpoint(
    q: Optional[str] = Query(None, description="Substring search in title/body"),
    pinned: Optional[bool] = Query(None),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await list_notes(db, user.id, q=q, pinned=pinned)


@notes_router.patch("/{note_id}", response_model=NoteResponse)
async def update_note_endpoint(
    note_id: int,
    data: NoteUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await update_note(db, user.id, note_id, data)


@notes_router.delete("/{note_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_note_endpoint(
    note_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await delete_note(db, user.id, note_id)


# ---------------------------------------------------------------------------
# Journal
# ---------------------------------------------------------------------------


@journal_router.put("/{entry_date}", response_model=JournalEntryResponse)
async def upsert_journal_entry_endpoint(
    entry_date: date,
    data: JournalEntryUpsert,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await upsert_journal_entry(db, user.id, entry_date, data)


@journal_router.get("", response_model=list[JournalEntryResponse])
async def list_journal_entries_endpoint(
    start_date: Optional[date] = Query(None),
    end_date: Optional[date] = Query(None),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await list_journal_entries(db, user.id, start_date=start_date, end_date=end_date)


@journal_router.delete("/{entry_date}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_journal_entry_endpoint(
    entry_date: date,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await delete_journal_entry(db, user.id, entry_date)


@journal_router.get("/{entry_date}/day")
async def get_day_summary_endpoint(
    entry_date: date,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await get_day_summary(db, user.id, entry_date)


router.include_router(notes_router)
router.include_router(journal_router)
