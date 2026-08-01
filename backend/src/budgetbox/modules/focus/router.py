from fastapi import APIRouter

from budgetbox.api.deps import SessionDep
from budgetbox.api.params import parse_month
from budgetbox.modules.focus import service
from budgetbox.modules.focus.models import FocusSession
from budgetbox.modules.focus.schemas import FocusIn, FocusOut, FocusPatch, StatsOut

router = APIRouter(prefix="/focus", tags=["focus"])


@router.get("/sessions")
def list_sessions(session: SessionDep, month: str | None = None) -> list[FocusOut]:
    rows = service.list_sessions(session, month=parse_month(month))
    return [FocusOut.model_validate(r) for r in rows]


@router.get("/stats")
def month_stats(session: SessionDep, month: str | None = None) -> StatsOut:
    return service.month_stats(session, month=parse_month(month))


@router.put("/sessions/{session_id}")
def upsert_session(session: SessionDep, session_id: str, data: FocusIn) -> FocusOut:
    return FocusOut.model_validate(service.upsert(session, session_id, data))


@router.patch("/sessions/{session_id}")
def patch_session(session: SessionDep, session_id: str, data: FocusPatch) -> FocusOut:
    return FocusOut.model_validate(service.patch(session, session_id, data))


from budgetbox.modules.changes.router import register  # noqa: E402

register("focus_sessions", FocusSession, FocusSession.id)
