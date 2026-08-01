from fastapi import APIRouter

from budgetbox.api.deps import SessionDep
from budgetbox.modules.notes import service
from budgetbox.modules.notes.models import Note
from budgetbox.modules.notes.schemas import NoteIn, NoteOut, NotePatch

router = APIRouter(prefix="/notes", tags=["notes"])


@router.get("")
def list_notes(session: SessionDep, include_archived: bool = False) -> list[NoteOut]:
    rows = service.list_notes(session, include_archived=include_archived)
    return [NoteOut.model_validate(r) for r in rows]


@router.put("/{note_id}")
def upsert_note(session: SessionDep, note_id: str, data: NoteIn) -> NoteOut:
    return NoteOut.model_validate(service.upsert(session, note_id, data))


@router.patch("/{note_id}")
def patch_note(session: SessionDep, note_id: str, data: NotePatch) -> NoteOut:
    """No DELETE: archiving is the delete, so a note is never actually lost."""
    return NoteOut.model_validate(service.patch(session, note_id, data))


from budgetbox.modules.changes.router import register  # noqa: E402

register("notes", Note, Note.id)
