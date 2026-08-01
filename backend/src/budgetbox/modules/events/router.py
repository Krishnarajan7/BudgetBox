import datetime as dt

from fastapi import APIRouter

from budgetbox.api.deps import SessionDep
from budgetbox.modules.events import service
from budgetbox.modules.events.models import Event
from budgetbox.modules.events.schemas import EventIn, EventOut, EventPatch, OccurrenceOut

router = APIRouter(prefix="/events", tags=["events"])


@router.get("")
def list_occurrences(
    session: SessionDep, from_day: dt.date, to_day: dt.date
) -> list[OccurrenceOut]:
    """Expanded occurrences for the window [from_day, to_day) — what a calendar draws."""
    return service.occurrences(session, from_day, to_day)


@router.get("/all")
def list_events(session: SessionDep, include_archived: bool = False) -> list[EventOut]:
    """Raw event rows (anchors) for the edit list."""
    rows = service.list_events(session, include_archived=include_archived)
    return [EventOut.model_validate(r) for r in rows]


@router.put("/{event_id}")
def upsert_event(session: SessionDep, event_id: str, data: EventIn) -> EventOut:
    return EventOut.model_validate(service.upsert(session, event_id, data))


@router.patch("/{event_id}")
def patch_event(session: SessionDep, event_id: str, data: EventPatch) -> EventOut:
    return EventOut.model_validate(service.patch(session, event_id, data))


from budgetbox.modules.changes.router import register  # noqa: E402

register("events", Event, Event.id)
