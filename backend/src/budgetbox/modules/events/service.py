import datetime as dt

from sqlalchemy import select
from sqlalchemy.orm import Session

from budgetbox.core.errors import NotFound
from budgetbox.core.ids import require_uuid
from budgetbox.domain.events import occurrences_between
from budgetbox.modules.events.models import Event, EventRepeat
from budgetbox.modules.events.schemas import EventIn, EventOut, EventPatch, OccurrenceOut


def get(session: Session, event_id: str) -> Event:
    row = session.get(Event, event_id)
    if row is None:
        raise NotFound(f"no event {event_id}")
    return row


def list_events(session: Session, *, include_archived: bool = False) -> list[Event]:
    """Raw rows for the edit list — anchors, not occurrences."""
    stmt = select(Event).order_by(Event.date, Event.title)
    if not include_archived:
        stmt = stmt.where(Event.archived.is_(False))
    return list(session.scalars(stmt))


def upsert(session: Session, event_id: str, data: EventIn) -> Event:
    event_id = require_uuid(event_id)
    row = session.get(Event, event_id)
    if row is None:
        row = Event(id=event_id)
        session.add(row)
    row.title = data.title
    row.note = data.note
    row.date = data.date
    row.time_minutes = data.time_minutes
    row.remind_minutes = data.remind_minutes
    row.repeat = data.repeat
    session.commit()
    return row


def patch(session: Session, event_id: str, data: EventPatch) -> Event:
    row = get(session, event_id)
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(row, field, value)
    session.commit()
    return row


def _sort_key(item: OccurrenceOut) -> tuple[dt.date, int, int, str]:
    """All-day (null time) sorts before anything timed on the same date."""
    timed = item.time_minutes is not None
    return (item.date, int(timed), item.time_minutes or 0, item.event.title)


def occurrences(session: Session, start: dt.date, end_exclusive: dt.date) -> list[OccurrenceOut]:
    """Every observance of every non-archived event inside [start, end)."""
    items: list[OccurrenceOut] = []
    for row in list_events(session):
        out = EventOut.model_validate(row)
        yearly = row.repeat is EventRepeat.YEARLY
        for day in occurrences_between(row.date, yearly, start, end_exclusive):
            items.append(OccurrenceOut(event=out, date=day, time_minutes=row.time_minutes))
    items.sort(key=_sort_key)
    return items
