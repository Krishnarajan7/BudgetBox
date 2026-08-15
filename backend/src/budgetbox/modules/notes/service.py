from sqlalchemy import select
from sqlalchemy.orm import Session

from budgetbox.core.errors import NotFound
from budgetbox.core.ids import require_uuid
from budgetbox.modules.notes.models import Note
from budgetbox.modules.notes.schemas import NoteIn, NotePatch


def list_notes(session: Session, *, include_archived: bool = False) -> list[Note]:
    """Pinned notes float to the top; within a group the freshest edit leads."""
    stmt = select(Note).order_by(Note.pinned.desc(), Note.updated_at.desc())
    if not include_archived:
        stmt = stmt.where(Note.archived.is_(False))
    return list(session.scalars(stmt))


def get(session: Session, note_id: str) -> Note:
    row = session.get(Note, note_id)
    if row is None:
        raise NotFound(f"no note {note_id}")
    return row


def upsert(session: Session, note_id: str, data: NoteIn) -> Note:
    """PUT semantics: create with the client's id, or full-replace in place.
    `archived` is deliberately untouched — un-archiving is an explicit PATCH,
    never a side effect of the editor autosaving a note."""
    note_id = require_uuid(note_id)
    row = session.get(Note, note_id)
    if row is None:
        row = Note(id=note_id)
        session.add(row)
    row.title = data.title
    row.body = data.body
    row.pinned = data.pinned
    row.remind_at = data.remind_at
    row.completed = data.completed
    session.commit()
    return row


def patch(session: Session, note_id: str, data: NotePatch) -> Note:
    row = get(session, note_id)
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(row, field, value)
    session.commit()
    return row
