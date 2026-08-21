"""The day's marks. Deliberately thin: the meaning of a `kind` lives in the app
(habit definitions travel as a setting), so this module stores, lists and drops
rows without ever asking what 'push' means."""

import datetime as dt

from sqlalchemy import select
from sqlalchemy.orm import Session

from budgetbox.core.errors import NotFound
from budgetbox.core.ids import require_uuid
from budgetbox.modules.marks.models import DayMark
from budgetbox.modules.marks.schemas import MarkIn


def list_marks(
    session: Session,
    *,
    from_day: dt.date | None = None,
    to_day: dt.date | None = None,
) -> list[DayMark]:
    """Marks in the closed day range, oldest first. No range means the whole
    record — it is one short row per habit per day, and a restoring phone
    wants all of it."""
    stmt = select(DayMark).order_by(DayMark.date, DayMark.at, DayMark.id)
    if from_day is not None:
        stmt = stmt.where(DayMark.date >= from_day)
    if to_day is not None:
        stmt = stmt.where(DayMark.date <= to_day)
    return list(session.scalars(stmt))


def get(session: Session, mark_id: str) -> DayMark:
    row = session.get(DayMark, mark_id)
    if row is None:
        raise NotFound(f"no mark {mark_id}")
    return row


def upsert(session: Session, mark_id: str, data: MarkIn) -> DayMark:
    mark_id = require_uuid(mark_id)
    row = session.get(DayMark, mark_id)
    if row is None:
        row = DayMark(id=mark_id)
        session.add(row)
    row.date = data.date
    row.kind = data.kind
    row.note = data.note
    row.at = data.at
    session.commit()
    return row


def delete(session: Session, mark_id: str) -> None:
    """Hard delete — un-ticking a habit removes the mark, and the tombstone in
    change_events is what tells the other phone to un-tick it too."""
    row = get(session, mark_id)
    session.delete(row)
    session.commit()
