from datetime import date as date_type
from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError
from app.models.mood_entry import MoodEntry
from app.models.water_log import WaterLog
from app.models.sleep_entry import SleepEntry

DEFAULT_WATER_GOAL = 8


async def _list_entries(
    db: AsyncSession,
    model,
    user_id: int,
    start_date: Optional[date_type],
    end_date: Optional[date_type],
):
    stmt = select(model).where(model.user_id == user_id)
    if start_date is not None:
        stmt = stmt.where(model.date >= start_date)
    if end_date is not None:
        stmt = stmt.where(model.date <= end_date)
    stmt = stmt.order_by(model.date.desc())

    result = await db.execute(stmt)
    return result.scalars().all()


async def _get_entry(db: AsyncSession, model, user_id: int, entry_date: date_type):
    result = await db.execute(
        select(model).where(model.user_id == user_id, model.date == entry_date)
    )
    return result.scalar_one_or_none()


async def _delete_entry(
    db: AsyncSession,
    model,
    user_id: int,
    entry_date: date_type,
    not_found_code: str,
):
    entry = await _get_entry(db, model, user_id, entry_date)
    if entry is None:
        raise AppError(not_found_code, "Entry not found", 404)

    await db.delete(entry)
    await db.commit()


# ---------------------------------------------------------------------------
# Mood
# ---------------------------------------------------------------------------


async def list_mood_entries(
    db: AsyncSession,
    user_id: int,
    start_date: Optional[date_type] = None,
    end_date: Optional[date_type] = None,
):
    return await _list_entries(db, MoodEntry, user_id, start_date, end_date)


async def upsert_mood_entry(
    db: AsyncSession,
    user_id: int,
    entry_date: date_type,
    data,
) -> MoodEntry:
    entry = await _get_entry(db, MoodEntry, user_id, entry_date)

    if entry is None:
        entry = MoodEntry(
            user_id=user_id,
            date=entry_date,
            mood=data.mood,
            note=data.note,
        )
        db.add(entry)
    else:
        entry.mood = data.mood
        entry.note = data.note

    await db.commit()
    await db.refresh(entry)
    return entry


async def delete_mood_entry(db: AsyncSession, user_id: int, entry_date: date_type):
    await _delete_entry(db, MoodEntry, user_id, entry_date, "MOOD_ENTRY_NOT_FOUND")


# ---------------------------------------------------------------------------
# Water
# ---------------------------------------------------------------------------


async def list_water_logs(
    db: AsyncSession,
    user_id: int,
    start_date: Optional[date_type] = None,
    end_date: Optional[date_type] = None,
):
    return await _list_entries(db, WaterLog, user_id, start_date, end_date)


async def upsert_water_log(
    db: AsyncSession,
    user_id: int,
    entry_date: date_type,
    data,
) -> WaterLog:
    entry = await _get_entry(db, WaterLog, user_id, entry_date)

    if entry is None:
        entry = WaterLog(
            user_id=user_id,
            date=entry_date,
            glasses=data.glasses,
            goal=data.goal if data.goal is not None else DEFAULT_WATER_GOAL,
        )
        db.add(entry)
    else:
        entry.glasses = data.glasses
        if data.goal is not None:
            entry.goal = data.goal

    await db.commit()
    await db.refresh(entry)
    return entry


async def delete_water_log(db: AsyncSession, user_id: int, entry_date: date_type):
    await _delete_entry(db, WaterLog, user_id, entry_date, "WATER_LOG_NOT_FOUND")


# ---------------------------------------------------------------------------
# Sleep
# ---------------------------------------------------------------------------


async def list_sleep_entries(
    db: AsyncSession,
    user_id: int,
    start_date: Optional[date_type] = None,
    end_date: Optional[date_type] = None,
):
    return await _list_entries(db, SleepEntry, user_id, start_date, end_date)


async def upsert_sleep_entry(
    db: AsyncSession,
    user_id: int,
    entry_date: date_type,
    data,
) -> SleepEntry:
    entry = await _get_entry(db, SleepEntry, user_id, entry_date)

    if entry is None:
        entry = SleepEntry(
            user_id=user_id,
            date=entry_date,
            hours=data.hours,
            quality=data.quality,
            bedtime=data.bedtime,
            wake_time=data.wake_time,
        )
        db.add(entry)
    else:
        entry.hours = data.hours
        entry.quality = data.quality
        entry.bedtime = data.bedtime
        entry.wake_time = data.wake_time

    await db.commit()
    await db.refresh(entry)
    return entry


async def delete_sleep_entry(db: AsyncSession, user_id: int, entry_date: date_type):
    await _delete_entry(db, SleepEntry, user_id, entry_date, "SLEEP_ENTRY_NOT_FOUND")
