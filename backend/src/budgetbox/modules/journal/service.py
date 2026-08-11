import datetime as dt
from datetime import date

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from budgetbox.core.errors import NotFound
from budgetbox.core.time import ist_day_start
from budgetbox.domain.insights import mood_money, streak_days
from budgetbox.domain.periods import days_in_month, month_end_exclusive, month_start
from budgetbox.modules.focus.models import FocusKind, FocusSession
from budgetbox.modules.journal.models import JournalEntry
from budgetbox.modules.journal.schemas import (
    DayFacts,
    JournalIn,
    JournalMonth,
    JournalOut,
    MoodMoneyOut,
)
from budgetbox.modules.notes.models import Note
from budgetbox.modules.transactions import service as txn_service
from budgetbox.modules.transactions.models import Txn, TxnType


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


def _written(row: JournalEntry) -> bool:
    """A page counts as written when it has words or a mood — an empty row created
    by a stray keystroke is not a day he showed up for."""
    return bool(row.body.strip()) or row.mood is not None


def day_facts(session: Session, day: date) -> DayFacts:
    """Money out, focus sat, notes written — the day as the rest of the box saw it."""
    start = ist_day_start(day)
    end = ist_day_start(day + dt.timedelta(days=1))

    spent, count = session.execute(
        select(func.coalesce(func.sum(Txn.amount_paise), 0), func.count(Txn.id)).where(
            Txn.type == TxnType.EXPENSE, Txn.at >= start, Txn.at < end
        )
    ).one()
    focus = session.scalar(
        select(func.coalesce(func.sum(FocusSession.minutes), 0)).where(
            FocusSession.kind == FocusKind.WORK,
            FocusSession.completed.is_(True),
            FocusSession.started_at >= start,
            FocusSession.started_at < end,
        )
    )
    notes = session.scalar(
        select(func.count(Note.id)).where(
            Note.archived.is_(False), Note.created_at >= start, Note.created_at < end
        )
    )
    return DayFacts(
        date=day,
        spent_paise=spent,
        txn_count=count,
        focus_minutes=focus or 0,
        notes_count=notes or 0,
    )


def month_view(session: Session, *, month: date, today: date) -> JournalMonth:
    """The journal's month: its pages, the mood grid, the streak, and — only when
    the evidence is real — what mood cost."""
    first = month_start(month)
    end = month_end_exclusive(first)
    rows = list_entries(session, first, end)

    dots: list[int | None] = [None] * days_in_month(first)
    for row in rows:
        dots[row.date.day - 1] = row.mood

    all_written = {row.date for row in session.scalars(select(JournalEntry)) if _written(row)}

    # Today is still being lived: its spend isn't a fair reading against its mood.
    spend = txn_service.money_by_day(session, first, min(end, today))
    pairs = [
        (row.mood, spend.get(row.date, (0, 0))[0])
        for row in rows
        if row.mood is not None and row.date < today
    ]
    verdict = mood_money(pairs)

    return JournalMonth(
        month=f"{first.year:04d}-{first.month:02d}",
        entries=[JournalOut.model_validate(r) for r in rows],
        mood_dots=dots,
        pages_written=sum(1 for r in rows if _written(r)),
        streak_days=streak_days(all_written, today),
        mood_money=(
            MoodMoneyOut(
                rough_days=verdict.rough_days,
                bright_days=verdict.bright_days,
                rough_avg_paise=verdict.rough_avg_paise,
                bright_avg_paise=verdict.bright_avg_paise,
                verdict=verdict.verdict,
            )
            if verdict is not None
            else None
        ),
    )
