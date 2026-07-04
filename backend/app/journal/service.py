from datetime import date as _date, datetime, timedelta
from typing import Optional

from sqlalchemy import select, or_
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.note import Note
from app.models.journal_entry import JournalEntry
from app.models.transaction import Transaction
from app.models.task import Task
from app.models.task_log import TaskLog
from app.models.habit import Habit
from app.models.habit_log import HabitLog
from app.core.errors import AppError

from app.journal.schemas import NoteCreate, NoteUpdate, JournalEntryUpsert


# ---------------------------------------------------------------------------
# Notes
# ---------------------------------------------------------------------------


async def create_note(
    db: AsyncSession,
    user_id: int,
    data: NoteCreate,
) -> Note:
    note = Note(
        user_id=user_id,
        title=data.title,
        body=data.body,
        pinned=data.pinned,
    )
    db.add(note)
    await db.commit()
    await db.refresh(note)
    return note


async def list_notes(
    db: AsyncSession,
    user_id: int,
    q: Optional[str] = None,
    pinned: Optional[bool] = None,
):
    query = select(Note).where(Note.user_id == user_id)

    if q:
        like = f"%{q}%"
        query = query.where(or_(Note.title.ilike(like), Note.body.ilike(like)))

    if pinned is not None:
        query = query.where(Note.pinned == pinned)

    query = query.order_by(Note.pinned.desc(), Note.updated_at.desc())

    result = await db.execute(query)
    return result.scalars().all()


async def update_note(
    db: AsyncSession,
    user_id: int,
    note_id: int,
    data: NoteUpdate,
) -> Note:
    result = await db.execute(
        select(Note).where(Note.id == note_id, Note.user_id == user_id)
    )
    note = result.scalar_one_or_none()
    if note is None:
        raise AppError("NOTE_NOT_FOUND", "Note not found", 404)

    if data.title is not None:
        note.title = data.title
    if data.body is not None:
        note.body = data.body
    if data.pinned is not None:
        note.pinned = data.pinned

    await db.commit()
    await db.refresh(note)
    return note


async def delete_note(
    db: AsyncSession,
    user_id: int,
    note_id: int,
):
    result = await db.execute(
        select(Note).where(Note.id == note_id, Note.user_id == user_id)
    )
    note = result.scalar_one_or_none()
    if note is None:
        raise AppError("NOTE_NOT_FOUND", "Note not found", 404)

    await db.delete(note)
    await db.commit()


# ---------------------------------------------------------------------------
# Journal entries
# ---------------------------------------------------------------------------


async def upsert_journal_entry(
    db: AsyncSession,
    user_id: int,
    entry_date: _date,
    data: JournalEntryUpsert,
) -> JournalEntry:
    result = await db.execute(
        select(JournalEntry).where(
            JournalEntry.user_id == user_id,
            JournalEntry.date == entry_date,
        )
    )
    entry = result.scalar_one_or_none()

    if entry:
        entry.body = data.body
        entry.mood_note = data.mood_note
    else:
        entry = JournalEntry(
            user_id=user_id,
            date=entry_date,
            body=data.body,
            mood_note=data.mood_note,
        )
        db.add(entry)

    await db.commit()
    await db.refresh(entry)
    return entry


async def list_journal_entries(
    db: AsyncSession,
    user_id: int,
    start_date: Optional[_date] = None,
    end_date: Optional[_date] = None,
):
    where = [JournalEntry.user_id == user_id]
    if start_date is not None:
        where.append(JournalEntry.date >= start_date)
    if end_date is not None:
        where.append(JournalEntry.date <= end_date)

    result = await db.execute(
        select(JournalEntry).where(*where).order_by(JournalEntry.date.desc())
    )
    return result.scalars().all()


async def delete_journal_entry(
    db: AsyncSession,
    user_id: int,
    entry_date: _date,
):
    result = await db.execute(
        select(JournalEntry).where(
            JournalEntry.user_id == user_id,
            JournalEntry.date == entry_date,
        )
    )
    entry = result.scalar_one_or_none()
    if entry is None:
        raise AppError("JOURNAL_ENTRY_NOT_FOUND", "Journal entry not found", 404)

    await db.delete(entry)
    await db.commit()


async def get_day_summary(
    db: AsyncSession,
    user_id: int,
    day: _date,
):
    day_start = datetime.combine(day, datetime.min.time())
    day_end = day_start + timedelta(days=1)

    # Journal entry for the day
    result = await db.execute(
        select(JournalEntry).where(
            JournalEntry.user_id == user_id,
            JournalEntry.date == day,
        )
    )
    entry = result.scalar_one_or_none()

    # Transactions that occurred that day
    result = await db.execute(
        select(Transaction)
        .where(
            Transaction.user_id == user_id,
            Transaction.occurred_at >= day_start,
            Transaction.occurred_at < day_end,
        )
        .order_by(Transaction.occurred_at.desc())
    )
    transactions = result.scalars().all()

    # Tasks completed that day
    result = await db.execute(
        select(Task)
        .join(TaskLog, TaskLog.task_id == Task.id)
        .where(
            Task.user_id == user_id,
            TaskLog.completed.is_(True),
            TaskLog.completed_at >= day_start,
            TaskLog.completed_at < day_end,
        )
    )
    tasks_completed = result.scalars().all()

    # Habits completed that day
    result = await db.execute(
        select(Habit)
        .join(HabitLog, HabitLog.habit_id == Habit.id)
        .where(
            Habit.user_id == user_id,
            HabitLog.date == day,
            HabitLog.completed.is_(True),
        )
    )
    habits_completed = result.scalars().all()

    entry_out = None
    if entry is not None:
        entry_out = {
            "id": entry.id,
            "date": entry.date,
            "body": entry.body,
            "mood_note": entry.mood_note,
            "created_at": entry.created_at,
            "updated_at": entry.updated_at,
        }

    return {
        "date": day,
        "entry": entry_out,
        "transactions": [
            {
                "id": tx.id,
                "type": tx.type.value if hasattr(tx.type, "value") else tx.type,
                "amount": float(tx.amount),
                "note": tx.note,
                "category_id": tx.category_id,
                "occurred_at": tx.occurred_at,
            }
            for tx in transactions
        ],
        "tasks_completed": [
            {"id": task.id, "title": task.title} for task in tasks_completed
        ],
        "habits_completed": [
            {"id": habit.id, "name": habit.name} for habit in habits_completed
        ],
    }
