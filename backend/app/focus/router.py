from datetime import date
from typing import Optional

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.auth.deps import get_current_user
from app.models.user import User

from app.focus.schemas import (
    FocusSessionCreate,
    FocusSessionResponse,
    FocusStatsResponse,
)
from app.focus.service import (
    create_focus_session,
    list_focus_sessions,
    delete_focus_session,
    get_focus_stats,
)


router = APIRouter(prefix="/focus", tags=["focus"])


@router.post(
    "/sessions",
    response_model=FocusSessionResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_focus_session_endpoint(
    data: FocusSessionCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await create_focus_session(db, user.id, data)


@router.get("/sessions", response_model=list[FocusSessionResponse])
async def list_focus_sessions_endpoint(
    start_date: Optional[date] = None,
    end_date: Optional[date] = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await list_focus_sessions(db, user.id, start_date, end_date)


@router.get("/stats", response_model=FocusStatsResponse)
async def get_focus_stats_endpoint(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await get_focus_stats(db, user.id)


@router.delete("/sessions/{session_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_focus_session_endpoint(
    session_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await delete_focus_session(db, user.id, session_id)
