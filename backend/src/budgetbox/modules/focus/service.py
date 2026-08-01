"""The focus ledger: every sitting — finished or abandoned — gets a line.
Months are IST months; `day_key` is the only place an instant becomes a day."""

import datetime as dt

from sqlalchemy import select
from sqlalchemy.orm import Session

from budgetbox.core.errors import NotFound
from budgetbox.core.ids import require_uuid
from budgetbox.core.time import day_key, ist_day_start, today_ist
from budgetbox.domain.periods import month_end_exclusive, month_start
from budgetbox.modules.focus.models import FocusKind, FocusSession
from budgetbox.modules.focus.schemas import FocusIn, FocusPatch, StatsOut


def get(session: Session, session_id: str) -> FocusSession:
    row = session.get(FocusSession, session_id)
    if row is None:
        raise NotFound(f"no focus session {session_id}")
    return row


def list_sessions(session: Session, *, month: dt.date | None = None) -> list[FocusSession]:
    """Sessions started inside the IST month (default: the current one), newest first."""
    first = month_start(month or today_ist())
    stmt = (
        select(FocusSession)
        .where(
            FocusSession.started_at >= ist_day_start(first),
            FocusSession.started_at < ist_day_start(month_end_exclusive(first)),
        )
        .order_by(FocusSession.started_at.desc())
    )
    return list(session.scalars(stmt))


def upsert(session: Session, session_id: str, data: FocusIn) -> FocusSession:
    session_id = require_uuid(session_id)
    row = session.get(FocusSession, session_id)
    if row is None:
        row = FocusSession(id=session_id)
        session.add(row)
    row.started_at = data.started_at
    row.minutes = data.minutes
    row.kind = data.kind
    row.completed = data.completed
    row.label = data.label
    session.commit()
    return row


def patch(session: Session, session_id: str, data: FocusPatch) -> FocusSession:
    row = get(session, session_id)
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(row, field, value)
    session.commit()
    return row


def month_stats(session: Session, *, month: dt.date | None = None) -> StatsOut:
    """The month's tally — completed work sessions only. Rest doesn't count toward
    it, and neither does a sitting he walked away from. Port of FocusRepo.monthStats."""
    rows = [
        r for r in list_sessions(session, month=month) if r.completed and r.kind is FocusKind.WORK
    ]
    total_minutes = 0
    by_day: dict[dt.date, int] = {}
    for row in rows:
        total_minutes += row.minutes
        day = day_key(row.started_at)
        by_day[day] = by_day.get(day, 0) + row.minutes

    best_day: dt.date | None = None
    best_day_minutes = 0
    for day in sorted(by_day):  # ascending, strict >: ties go to the earlier day
        if by_day[day] > best_day_minutes:
            best_day, best_day_minutes = day, by_day[day]

    return StatsOut(
        total_minutes=total_minutes,
        sessions=len(rows),
        best_day=best_day,
        best_day_minutes=best_day_minutes,
    )
