"""/v1/marks — the day's non-money marks: habits kept, meals eaten, slips."""

from datetime import date

from fastapi import APIRouter

from budgetbox.api.deps import SessionDep
from budgetbox.modules.marks import service
from budgetbox.modules.marks.schemas import MarkIn, MarkOut

router = APIRouter(prefix="/marks", tags=["marks"])


@router.get("")
def list_marks(
    session: SessionDep,
    from_day: date | None = None,
    to_day: date | None = None,
) -> list[MarkOut]:
    rows = service.list_marks(session, from_day=from_day, to_day=to_day)
    return [MarkOut.model_validate(r) for r in rows]


@router.put("/{mark_id}")
def upsert_mark(session: SessionDep, mark_id: str, data: MarkIn) -> MarkOut:
    return MarkOut.model_validate(service.upsert(session, mark_id, data))


@router.delete("/{mark_id}", status_code=204)
def delete_mark(session: SessionDep, mark_id: str) -> None:
    service.delete(session, mark_id)
