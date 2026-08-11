"""The focus ledger: every sitting — finished or abandoned — gets a line.
Months are IST months; `day_key` is the only place an instant becomes a day."""

import datetime as dt

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from budgetbox.core.errors import NotFound
from budgetbox.core.ids import require_uuid
from budgetbox.core.time import day_key, ist_day_start, today_ist
from budgetbox.domain.insights import streak_days
from budgetbox.domain.periods import month_end_exclusive, month_start
from budgetbox.modules.focus.models import FocusKind, FocusSession
from budgetbox.modules.focus.schemas import (
    DayMinutes,
    FocusIn,
    FocusPatch,
    FocusRecord,
    StatsOut,
)


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


def _best_day(by_day: dict[dt.date, int]) -> tuple[dt.date | None, int]:
    best_day: dt.date | None = None
    best_minutes = 0
    for day in sorted(by_day):  # ascending, strict >: ties go to the earlier day
        if by_day[day] > best_minutes:
            best_day, best_minutes = day, by_day[day]
    return best_day, best_minutes


def record(session: Session) -> FocusRecord:
    """The all-time book: completed work only, no month bound."""
    rows = list(
        session.scalars(
            select(FocusSession)
            .where(FocusSession.completed.is_(True), FocusSession.kind == FocusKind.WORK)
            .order_by(FocusSession.started_at)
        )
    )
    by_day: dict[dt.date, int] = {}
    longest_minutes = 0
    longest_at: dt.datetime | None = None
    for row in rows:
        day = day_key(row.started_at)
        by_day[day] = by_day.get(day, 0) + row.minutes
        if row.minutes > longest_minutes:  # ties go to the earlier sitting
            longest_minutes, longest_at = row.minutes, row.started_at
    best_day, best_day_minutes = _best_day(by_day)
    return FocusRecord(
        total_minutes=sum(r.minutes for r in rows),
        sessions=len(rows),
        longest_minutes=longest_minutes,
        longest_at=longest_at,
        best_day=best_day,
        best_day_minutes=best_day_minutes,
        streak_days=streak_days(set(by_day), today_ist()),
    )


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

    best_day, best_day_minutes = _best_day(by_day)

    today = today_ist()
    monday = today - dt.timedelta(days=today.weekday())
    week = [0] * 7
    week_rows = session.scalars(
        select(FocusSession).where(
            FocusSession.completed.is_(True),
            FocusSession.kind == FocusKind.WORK,
            FocusSession.started_at >= ist_day_start(monday),
            FocusSession.started_at < ist_day_start(monday + dt.timedelta(days=7)),
        )
    )
    for row in week_rows:
        week[(day_key(row.started_at) - monday).days] += row.minutes

    # Today's tally counts an abandoned sitting too: the minutes were still sat.
    today_minutes = session.scalar(
        select(func.coalesce(func.sum(FocusSession.minutes), 0)).where(
            FocusSession.kind == FocusKind.WORK,
            FocusSession.started_at >= ist_day_start(today),
            FocusSession.started_at < ist_day_start(today + dt.timedelta(days=1)),
        )
    )

    return StatsOut(
        total_minutes=total_minutes,
        sessions=len(rows),
        best_day=best_day,
        best_day_minutes=best_day_minutes,
        day_minutes=[DayMinutes(date=day, minutes=by_day[day]) for day in sorted(by_day)],
        week_minutes=week,
        today_work_minutes=today_minutes or 0,
        record=record(session),
    )
