"""The whole server copy, seen and destroyed: row counts per table, and the
one deliberate act that empties them all. Built for a book under test —
stamps pile up server-side; the owner may sweep the shelf clean."""

from fastapi import APIRouter
from sqlalchemy import delete, func, select

from budgetbox.api.deps import SessionDep
from budgetbox.api.schemas import APIModel
from budgetbox.db.base import Base

router = APIRouter(prefix="/book", tags=["book"])

# The tokens table is the door itself — never counted as content, never
# erased from here: a wiped book must still answer to its owner.
_KEEP = {"device_tokens"}


class BookStatsOut(APIModel):
    counts: dict[str, int]
    total: int


@router.get("/stats")
def stats(session: SessionDep) -> BookStatsOut:
    """How many rows of the owner's life this server is holding, per table.
    Empty tables stay out of the answer — zeroes are noise."""
    counts: dict[str, int] = {}
    for table in Base.metadata.sorted_tables:
        if table.name in _KEEP:
            continue
        n = session.scalar(select(func.count()).select_from(table)) or 0
        if n:
            counts[table.name] = n
    return BookStatsOut(counts=counts, total=sum(counts.values()))


class EraseOut(APIModel):
    erased: int


@router.post("/erase")
def erase(session: SessionDep) -> EraseOut:
    """Deletes every content row, permanently — children before parents so
    foreign keys never object. The change log is swept LAST: the triggers
    watching every table write fresh tombstones during the sweep itself,
    and an erased book must leave no tombstones to resurrect it."""
    erased = 0
    log = Base.metadata.tables["change_events"]
    for table in reversed(Base.metadata.sorted_tables):
        if table.name in _KEEP or table is log:
            continue
        erased += session.scalar(select(func.count()).select_from(table)) or 0
        session.execute(delete(table))
    erased += session.scalar(select(func.count()).select_from(log)) or 0
    session.execute(delete(log))
    session.commit()
    return EraseOut(erased=erased)
