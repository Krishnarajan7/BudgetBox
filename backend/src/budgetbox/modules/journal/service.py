from datetime import date

from sqlalchemy import select
from sqlalchemy.orm import Session

from budgetbox.core.errors import NotFound
from budgetbox.modules.journal.models import JournalEntry
from budgetbox.modules.journal.schemas import JournalIn


def list_entries(session: Session, from_day: date, to_day: date) -> list[JournalEntry]:
    """Newest day first. Bounds are IST days: from_day inclusive, to_day exclusive."""
    stmt = (
        select(JournalEntry)
        .where(JournalEntry.date >= from_day, JournalEntry.date < to_day)
        .order_by(JournalEntry.date.desc())
    )
    return list(session.scalars(stmt))


def get(session: Session, day: date) -> JournalEntry:
    row = session.get(JournalEntry, day)
    if row is None:
        raise NotFound(f"no journal entry for {day.isoformat()}")
    return row


def upsert(session: Session, day: date, data: JournalIn) -> JournalEntry:
    """PUT semantics: writing the same day again replaces the entry in place."""
    row = session.get(JournalEntry, day)
    if row is None:
        row = JournalEntry(date=day)
        session.add(row)
    row.body = data.body
    row.mood = data.mood
    session.commit()
    return row


def delete(session: Session, day: date) -> None:
    """Hard delete — a journal entry is the user's own words; no tombstone kept."""
    row = get(session, day)
    session.delete(row)
    session.commit()
