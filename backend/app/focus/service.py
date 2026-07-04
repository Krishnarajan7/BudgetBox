from datetime import date, datetime, time, timedelta
from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError
from app.models.focus_session import FocusSession


async def create_focus_session(
    db: AsyncSession,
    user_id: int,
    data,
) -> FocusSession:
    session = FocusSession(
        user_id=user_id,
        started_at=data.started_at,
        duration_min=data.duration_min,
        kind=data.kind,
        label=data.label,
        completed=data.completed,
    )
    db.add(session)
    await db.commit()
    await db.refresh(session)
    return session


async def list_focus_sessions(
    db: AsyncSession,
    user_id: int,
    start_date: Optional[date] = None,
    end_date: Optional[date] = None,
):
    stmt = select(FocusSession).where(FocusSession.user_id == user_id)

    if start_date is not None:
        start_datetime = datetime.combine(start_date, time.min)
        stmt = stmt.where(FocusSession.started_at >= start_datetime)

    if end_date is not None:
        end_datetime_exclusive = datetime.combine(end_date, time.min) + timedelta(days=1)
        stmt = stmt.where(FocusSession.started_at < end_datetime_exclusive)

    stmt = stmt.order_by(FocusSession.started_at.desc())

    result = await db.execute(stmt)
    return result.scalars().all()


async def delete_focus_session(db: AsyncSession, user_id: int, session_id: int):
    result = await db.execute(
        select(FocusSession).where(
            FocusSession.id == session_id,
            FocusSession.user_id == user_id,
        )
    )
    session = result.scalar_one_or_none()
    if session is None:
        raise AppError("FOCUS_SESSION_NOT_FOUND", "Focus session not found", 404)

    await db.delete(session)
    await db.commit()


def _to_local_naive(dt: datetime) -> datetime:
    # Postgres returns tz-aware datetimes (DateTime(timezone=True)); SQLite
    # returns naive ones. Normalize to local naive so comparisons against
    # date.today()-based boundaries work on both.
    if dt.tzinfo is not None:
        return dt.astimezone().replace(tzinfo=None)
    return dt


async def get_focus_stats(db: AsyncSession, user_id: int) -> dict:
    today = date.today()
    today_start = datetime.combine(today, time.min)
    tomorrow_start = today_start + timedelta(days=1)
    week_start = datetime.combine(today - timedelta(days=6), time.min)

    # Only "work" sessions count toward focus minutes / session counts -
    # breaks aren't focus time.
    result = await db.execute(
        select(FocusSession).where(
            FocusSession.user_id == user_id,
            FocusSession.kind == "work",
            FocusSession.started_at >= week_start,
            FocusSession.started_at < tomorrow_start,
        )
    )
    week_work_sessions = result.scalars().all()

    today_minutes = 0
    week_minutes = 0
    today_sessions = 0
    week_sessions = 0

    for session in week_work_sessions:
        week_minutes += session.duration_min
        week_sessions += 1
        if _to_local_naive(session.started_at) >= today_start:
            today_minutes += session.duration_min
            today_sessions += 1

    current_streak_days = await _current_streak_days(db, user_id, today)

    return {
        "today_minutes": today_minutes,
        "week_minutes": week_minutes,
        "today_sessions": today_sessions,
        "week_sessions": week_sessions,
        "current_streak_days": current_streak_days,
    }


async def _current_streak_days(db: AsyncSession, user_id: int, today: date) -> int:
    result = await db.execute(
        select(FocusSession.started_at)
        .where(
            FocusSession.user_id == user_id,
            FocusSession.kind == "work",
            FocusSession.completed == True,  # noqa: E712
        )
        .order_by(FocusSession.started_at.desc())
    )
    completed_dates = sorted(
        {_to_local_naive(row[0]).date() for row in result.all()}, reverse=True
    )

    if not completed_dates:
        return 0

    if completed_dates[0] not in (today, today - timedelta(days=1)):
        return 0

    streak = 1
    expected = completed_dates[0] - timedelta(days=1)
    for day in completed_dates[1:]:
        if day == expected:
            streak += 1
            expected -= timedelta(days=1)
        else:
            break

    return streak
