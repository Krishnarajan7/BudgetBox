from datetime import date

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.auth.deps import get_current_user
from app.models.user import User

from app.calendar_events.schemas import (
    EventCreate,
    EventUpdate,
    EventResponse,
    CalendarResponse,
)
from app.calendar_events.service import (
    create_event,
    list_events,
    update_event,
    delete_event,
    get_calendar_month,
)

# No prefix: this router owns both the /events collection and the
# unified /calendar month view, so paths are declared explicitly below.
router = APIRouter(tags=["calendar"])


@router.post("/events", response_model=EventResponse, status_code=status.HTTP_201_CREATED)
async def create_event_endpoint(
    data: EventCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await create_event(db, user.id, data)


@router.get("/events", response_model=list[EventResponse])
async def list_events_endpoint(
    start_date: date | None = Query(None),
    end_date: date | None = Query(None),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await list_events(db, user.id, start_date, end_date)


@router.patch("/events/{event_id}", response_model=EventResponse)
async def update_event_endpoint(
    event_id: int,
    data: EventUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await update_event(db, user.id, event_id, data)


@router.delete("/events/{event_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_event_endpoint(
    event_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await delete_event(db, user.id, event_id)


@router.get("/calendar", response_model=CalendarResponse)
async def calendar_month_endpoint(
    month: str | None = Query(None, description="YYYY-MM, defaults to current month"),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await get_calendar_month(db, user.id, month)
