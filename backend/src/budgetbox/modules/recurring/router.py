from datetime import date, timedelta

from fastapi import APIRouter

from budgetbox.api.deps import SessionDep
from budgetbox.core.time import today_ist
from budgetbox.modules.recurring import service
from budgetbox.modules.recurring.schemas import (
    RecurringIn,
    RecurringOut,
    RecurringPatch,
    UpcomingOut,
)

router = APIRouter(prefix="/recurring", tags=["recurring"])


@router.get("")
def list_recurrings(session: SessionDep, include_inactive: bool = False) -> list[RecurringOut]:
    rows = service.list_recurrings(session, include_inactive=include_inactive)
    return [RecurringOut.model_validate(r) for r in rows]


@router.get("/upcoming")
def upcoming(session: SessionDep, until: date | None = None) -> UpcomingOut:
    horizon = until or (today_ist() + timedelta(days=30))
    return UpcomingOut(
        items=service.upcoming(session, until=horizon),
        committed_monthly_paise=service.committed_monthly_paise(session),
    )


@router.put("/{recurring_id}")
def upsert_recurring(session: SessionDep, recurring_id: str, data: RecurringIn) -> RecurringOut:
    return RecurringOut.model_validate(service.upsert(session, recurring_id, data))


@router.patch("/{recurring_id}")
def patch_recurring(session: SessionDep, recurring_id: str, data: RecurringPatch) -> RecurringOut:
    return RecurringOut.model_validate(service.patch(session, recurring_id, data))


@router.delete("/{recurring_id}")
def deactivate_recurring(session: SessionDep, recurring_id: str) -> RecurringOut:
    """Deactivate (history keeps its txns); there is no hard delete."""
    return RecurringOut.model_validate(service.deactivate(session, recurring_id))
