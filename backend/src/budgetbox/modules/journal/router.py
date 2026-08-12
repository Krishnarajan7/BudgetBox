from datetime import date

from fastapi import APIRouter

from budgetbox.api.deps import SessionDep
from budgetbox.api.params import parse_month
from budgetbox.core.time import today_ist
from budgetbox.modules.journal import service
from budgetbox.modules.journal.schemas import DayFacts, JournalIn, JournalMonth, JournalOut

router = APIRouter(prefix="/journal", tags=["journal"])


@router.get("")
def list_entries(session: SessionDep, from_day: date, to_day: date) -> list[JournalOut]:
    rows = service.list_entries(session, from_day, to_day)
    return [JournalOut.model_validate(r) for r in rows]


# Declared before /{day} so 'month' is never parsed as a date.
@router.get("/month")
def month_view(session: SessionDep, month: str | None = None) -> JournalMonth:
    """The month's pages, mood grid, streak, and the mood-against-money whisper."""
    today = today_ist()
    return service.month_view(session, month=parse_month(month) or today, today=today)


@router.get("/{day}")
def get_entry(session: SessionDep, day: date) -> JournalOut:
    return JournalOut.model_validate(service.get(session, day))


@router.get("/{day}/facts")
def day_facts(session: SessionDep, day: date) -> DayFacts:
    """What the rest of the box knows about the day — money out, focus sat, notes
    written. Answers even for a blank page, which is the point."""
    return service.day_facts(session, day)


@router.put("/{day}")
def upsert_entry(session: SessionDep, day: date, data: JournalIn) -> JournalOut:
    return JournalOut.model_validate(service.upsert(session, day, data))


@router.delete("/{day}", status_code=204)
def delete_entry(session: SessionDep, day: date) -> None:
    service.delete(session, day)
