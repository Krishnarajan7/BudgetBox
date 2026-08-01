from datetime import date

from fastapi import APIRouter

from budgetbox.api.deps import SessionDep
from budgetbox.modules.journal import service
from budgetbox.modules.journal.models import JournalEntry
from budgetbox.modules.journal.schemas import JournalIn, JournalOut

router = APIRouter(prefix="/journal", tags=["journal"])


@router.get("")
def list_entries(session: SessionDep, from_day: date, to_day: date) -> list[JournalOut]:
    rows = service.list_entries(session, from_day, to_day)
    return [JournalOut.model_validate(r) for r in rows]


@router.get("/{day}")
def get_entry(session: SessionDep, day: date) -> JournalOut:
    return JournalOut.model_validate(service.get(session, day))


@router.put("/{day}")
def upsert_entry(session: SessionDep, day: date, data: JournalIn) -> JournalOut:
    return JournalOut.model_validate(service.upsert(session, day, data))


@router.delete("/{day}", status_code=204)
def delete_entry(session: SessionDep, day: date) -> None:
    service.delete(session, day)


from budgetbox.modules.changes.router import register  # noqa: E402

register("journal_entries", JournalEntry, JournalEntry.date)
