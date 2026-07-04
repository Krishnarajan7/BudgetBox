from datetime import date

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Optional

from app.core.database import get_db
from app.auth.deps import get_current_user
from app.models.user import User

from app.wellness.schemas import (
    MoodUpsert,
    MoodResponse,
    WaterUpsert,
    WaterResponse,
    SleepUpsert,
    SleepResponse,
)
from app.wellness.service import (
    list_mood_entries,
    upsert_mood_entry,
    delete_mood_entry,
    list_water_logs,
    upsert_water_log,
    delete_water_log,
    list_sleep_entries,
    upsert_sleep_entry,
    delete_sleep_entry,
)


mood_router = APIRouter(prefix="/mood", tags=["wellness-mood"])
water_router = APIRouter(prefix="/water", tags=["wellness-water"])
sleep_router = APIRouter(prefix="/sleep", tags=["wellness-sleep"])


# ---------------------------------------------------------------------------
# Mood
# ---------------------------------------------------------------------------


@mood_router.get("", response_model=list[MoodResponse])
async def list_mood_entries_endpoint(
    start_date: Optional[date] = None,
    end_date: Optional[date] = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await list_mood_entries(db, user.id, start_date, end_date)


@mood_router.put("/{entry_date}", response_model=MoodResponse)
async def upsert_mood_entry_endpoint(
    entry_date: date,
    data: MoodUpsert,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await upsert_mood_entry(db, user.id, entry_date, data)


@mood_router.delete("/{entry_date}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_mood_entry_endpoint(
    entry_date: date,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await delete_mood_entry(db, user.id, entry_date)


# ---------------------------------------------------------------------------
# Water
# ---------------------------------------------------------------------------


@water_router.get("", response_model=list[WaterResponse])
async def list_water_logs_endpoint(
    start_date: Optional[date] = None,
    end_date: Optional[date] = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await list_water_logs(db, user.id, start_date, end_date)


@water_router.put("/{entry_date}", response_model=WaterResponse)
async def upsert_water_log_endpoint(
    entry_date: date,
    data: WaterUpsert,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await upsert_water_log(db, user.id, entry_date, data)


@water_router.delete("/{entry_date}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_water_log_endpoint(
    entry_date: date,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await delete_water_log(db, user.id, entry_date)


# ---------------------------------------------------------------------------
# Sleep
# ---------------------------------------------------------------------------


@sleep_router.get("", response_model=list[SleepResponse])
async def list_sleep_entries_endpoint(
    start_date: Optional[date] = None,
    end_date: Optional[date] = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await list_sleep_entries(db, user.id, start_date, end_date)


@sleep_router.put("/{entry_date}", response_model=SleepResponse)
async def upsert_sleep_entry_endpoint(
    entry_date: date,
    data: SleepUpsert,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await upsert_sleep_entry(db, user.id, entry_date, data)


@sleep_router.delete("/{entry_date}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_sleep_entry_endpoint(
    entry_date: date,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await delete_sleep_entry(db, user.id, entry_date)
