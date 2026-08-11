from datetime import date

from fastapi import APIRouter, Query

from budgetbox.api.deps import SessionDep
from budgetbox.core.time import today_ist
from budgetbox.modules.transactions import service
from budgetbox.modules.transactions.models import TxnType
from budgetbox.modules.transactions.schemas import (
    ActivityOut,
    PinnedBoard,
    PinnedIn,
    PinnedOut,
    RecentAmount,
    SealOut,
    StampIn,
    TitleSuggestion,
    TxnIn,
    TxnOut,
    TxnPage,
    TxnPatch,
    UndoResult,
)

router = APIRouter(tags=["ledger"])

txns = APIRouter(prefix="/txns")
pinned = APIRouter(prefix="/pinned")
seals = APIRouter(prefix="/seals")
activities = APIRouter(prefix="/activities")


@txns.get("")
def list_txns(
    session: SessionDep,
    from_day: date | None = None,
    to_day: date | None = None,
    category_id: str | None = None,
    account_id: str | None = None,
    type: TxnType | None = None,
    q: str | None = None,
    limit: int = Query(default=100, ge=1, le=500),
    cursor: str | None = None,
) -> TxnPage:
    rows, next_cursor = service.list_txns(
        session,
        from_day=from_day,
        to_day=to_day,
        category_id=category_id,
        account_id=account_id,
        type_=type,
        q=q,
        limit=limit,
        cursor=cursor,
    )
    return TxnPage(items=[TxnOut.model_validate(r) for r in rows], next_cursor=next_cursor)


@txns.get("/suggest")
def suggest_titles(
    session: SessionDep, q: str = Query(min_length=1), limit: int = Query(default=6, ge=1, le=20)
) -> list[TitleSuggestion]:
    return service.suggest_titles(session, q, limit=limit)


@txns.get("/recent-amounts")
def recent_amounts(
    session: SessionDep, category_id: str, limit: int = Query(default=3, ge=1, le=10)
) -> list[RecentAmount]:
    """The amounts this category is usually written for — the add sheet's whisper."""
    return service.recent_amounts(session, category_id, limit=limit)


@txns.get("/{txn_id}")
def get_txn(session: SessionDep, txn_id: str) -> TxnOut:
    return TxnOut.model_validate(service.get(session, txn_id))


@txns.put("/{txn_id}")
def upsert_txn(session: SessionDep, txn_id: str, data: TxnIn) -> TxnOut:
    row, _created = service.upsert(session, txn_id, data)
    return TxnOut.model_validate(row)


@txns.patch("/{txn_id}")
def patch_txn(session: SessionDep, txn_id: str, data: TxnPatch) -> TxnOut:
    return TxnOut.model_validate(service.patch(session, txn_id, data))


@txns.delete("/{txn_id}", status_code=204)
def delete_txn(session: SessionDep, txn_id: str) -> None:
    service.delete(session, txn_id)


@activities.get("")
def recent_activities(
    session: SessionDep,
    limit: int = Query(default=20, ge=1, le=500),
    txn_id: str | None = None,
) -> list[ActivityOut]:
    """The audit trail, newest first. `txn_id` narrows it to one entry's rewrites —
    what the editor's 'rewritten twice · last on 12 Jul' whisper reads."""
    rows = service.recent_activities(session, limit=limit, txn_id=txn_id)
    return [service.activity_out(session, a) for a in rows]


@activities.post("/{activity_id}/undo")
def undo_activity(session: SessionDep, activity_id: str) -> UndoResult:
    action, txn = service.undo(session, activity_id)
    return UndoResult(action=action, txn=TxnOut.model_validate(txn) if txn else None)


@pinned.get("")
def list_pinned(session: SessionDep) -> list[PinnedOut]:
    return [PinnedOut.model_validate(p) for p in service.list_pinned(session)]


@pinned.get("/board")
def pinned_board(session: SessionDep) -> PinnedBoard:
    """The pinned manager in one call: pins with their stamp counts, plus repeats
    worth pinning that aren't pinned yet."""
    return service.pinned_board(session, today=today_ist())


@pinned.put("/{pinned_id}")
def upsert_pinned(session: SessionDep, pinned_id: str, data: PinnedIn) -> PinnedOut:
    return PinnedOut.model_validate(service.upsert_pinned(session, pinned_id, data))


@pinned.delete("/{pinned_id}", status_code=204)
def delete_pinned(session: SessionDep, pinned_id: str) -> None:
    service.delete_pinned(session, pinned_id)


@pinned.post("/{pinned_id}/stamp", status_code=201)
def stamp_pinned(session: SessionDep, pinned_id: str, data: StampIn | None = None) -> TxnOut:
    at = data.at if data else None
    return TxnOut.model_validate(service.stamp_pinned(session, pinned_id, at))


@seals.get("")
def seals_between(session: SessionDep, from_day: date, to_day: date) -> list[SealOut]:
    return [SealOut.model_validate(s) for s in service.seals_between(session, from_day, to_day)]


@seals.put("/{day}")
def seal_day(session: SessionDep, day: date) -> SealOut:
    return SealOut.model_validate(service.seal_day(session, day))


@seals.delete("/{day}", status_code=204)
def unseal_day(session: SessionDep, day: date) -> None:
    """Reopen a closed page. Idempotent — an unsealed day unseals fine."""
    service.unseal_day(session, day)


for sub in (txns, activities, pinned, seals):
    router.include_router(sub)
