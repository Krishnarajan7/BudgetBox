"""Ledger write path. Port of TxnRepo semantics: every mutation logs an Activity
snapshot in the same transaction, and undo replays the inverse. Balances are never
written — they derive from anchors + this ledger (see accounts.service)."""

import json
from datetime import date, datetime

from sqlalchemy import and_, func, or_, select
from sqlalchemy.orm import Session

from budgetbox.api.pagination import decode_cursor, encode_cursor
from budgetbox.core.errors import Conflict, Invalid, NotFound
from budgetbox.core.ids import new_id, require_uuid
from budgetbox.core.money import Paise
from budgetbox.core.time import ist_day_start, now_utc
from budgetbox.modules.accounts.models import Account
from budgetbox.modules.categories.models import Category
from budgetbox.modules.transactions.models import (
    Activity,
    ActivityAction,
    DaySeal,
    Pinned,
    Txn,
    TxnType,
)
from budgetbox.modules.transactions.schemas import (
    PinnedIn,
    TitleSuggestion,
    TxnIn,
    TxnOut,
    TxnPatch,
)

_SNAPSHOT_SCHEMA = 1

_TXN_FIELDS = (
    "amount_paise",
    "type",
    "account_id",
    "to_account_id",
    "category_id",
    "title",
    "note",
    "at",
    "goal_id",
)


# --- validation ---------------------------------------------------------------


def _require_account(session: Session, account_id: str) -> None:
    if session.get(Account, account_id) is None:
        raise Invalid(f"no account {account_id}")


def _validate_shape(session: Session, row: Txn) -> None:
    _require_account(session, row.account_id)
    if row.type is TxnType.TRANSFER:
        if row.to_account_id is None:
            raise Invalid("a transfer needs to_account_id")
        if row.to_account_id == row.account_id:
            raise Invalid("a transfer needs two different accounts")
        if row.category_id is not None:
            raise Invalid("transfers carry no category")
        _require_account(session, row.to_account_id)
    else:
        if row.to_account_id is not None:
            raise Invalid("to_account_id is only for transfers")
        if row.category_id is not None and session.get(Category, row.category_id) is None:
            raise Invalid(f"no category {row.category_id}")
    if row.goal_id is not None:
        from budgetbox.modules.goals.models import Goal

        if session.get(Goal, row.goal_id) is None:
            raise Invalid(f"no goal {row.goal_id}")


# --- activity snapshots -------------------------------------------------------


def _snapshot(row: Txn) -> str:
    return json.dumps(
        {"schema": _SNAPSHOT_SCHEMA, "txn": TxnOut.model_validate(row).model_dump(mode="json")}
    )


def _row_from_snapshot(raw: str) -> Txn:
    payload = json.loads(raw)
    data = TxnOut.model_validate(payload["txn"])
    return Txn(
        id=data.id,
        amount_paise=data.amount_paise,
        type=data.type,
        account_id=data.account_id,
        to_account_id=data.to_account_id,
        category_id=data.category_id,
        title=data.title,
        note=data.note,
        at=data.at,
        goal_id=data.goal_id,
        recurring_id=data.recurring_id,
        created_at=data.created_at,
        updated_at=data.updated_at,
    )


def _log(session: Session, txn_id: str, action: ActivityAction, snapshot: str) -> None:
    session.add(
        Activity(id=new_id(), txn_id=txn_id, action=action, snapshot=snapshot, at=now_utc())
    )


# --- txn writes ---------------------------------------------------------------


def get(session: Session, txn_id: str) -> Txn:
    row = session.get(Txn, txn_id)
    if row is None:
        raise NotFound(f"no txn {txn_id}")
    return row


def upsert(
    session: Session, txn_id: str, data: TxnIn, *, recurring_id: str | None = None
) -> tuple[Txn, bool]:
    """PUT semantics; a blind retry of the same payload is a no-op, which is what
    lets the phone queue writes offline and resend safely. Returns (row, created)."""
    txn_id = require_uuid(txn_id)
    row = session.get(Txn, txn_id)
    if row is None:
        row = Txn(id=txn_id, recurring_id=recurring_id)
        for field in _TXN_FIELDS:
            setattr(row, field, getattr(data, field))
        _validate_shape(session, row)
        session.add(row)
        session.flush()
        _log(session, txn_id, ActivityAction.CREATED, _snapshot(row))
        session.commit()
        return row, True

    if all(getattr(row, f) == getattr(data, f) for f in _TXN_FIELDS):
        return row, False  # idempotent retry
    before = _snapshot(row)
    for field in _TXN_FIELDS:
        setattr(row, field, getattr(data, field))
    _validate_shape(session, row)
    _log(session, txn_id, ActivityAction.EDITED, before)
    session.commit()
    return row, False


def patch(session: Session, txn_id: str, data: TxnPatch) -> Txn:
    row = get(session, txn_id)
    changes = data.model_dump(exclude_unset=True)
    if not changes:
        return row
    before = _snapshot(row)
    for field, value in changes.items():
        setattr(row, field, value)
    _validate_shape(session, row)
    _log(session, txn_id, ActivityAction.EDITED, before)
    session.commit()
    return row


def delete(session: Session, txn_id: str) -> None:
    row = get(session, txn_id)
    _log(session, txn_id, ActivityAction.DELETED, _snapshot(row))
    session.delete(row)
    session.commit()


def undo(session: Session, activity_id: str) -> tuple[ActivityAction, Txn | None]:
    """Replay the inverse of a logged action, consuming the activity row."""
    activity = session.get(Activity, activity_id)
    if activity is None:
        raise NotFound(f"no activity {activity_id}")
    result: Txn | None = None
    match activity.action:
        case ActivityAction.CREATED:
            row = session.get(Txn, activity.txn_id)
            if row is not None:
                session.delete(row)
        case ActivityAction.EDITED:
            row = session.get(Txn, activity.txn_id)
            if row is None:
                raise Conflict("the edited txn no longer exists; undo the delete first")
            restored = _row_from_snapshot(activity.snapshot)
            for field in _TXN_FIELDS:
                setattr(row, field, getattr(restored, field))
            result = row
        case ActivityAction.DELETED:
            if session.get(Txn, activity.txn_id) is not None:
                raise Conflict("a txn with this id exists again; nothing to undo")
            restored = _row_from_snapshot(activity.snapshot)
            session.add(restored)
            result = restored
    action = activity.action
    session.delete(activity)
    session.commit()
    return action, result


def recent_activities(session: Session, *, limit: int = 20) -> list[Activity]:
    stmt = select(Activity).order_by(Activity.at.desc(), Activity.id.desc()).limit(limit)
    return list(session.scalars(stmt))


# --- txn reads ----------------------------------------------------------------


def list_txns(
    session: Session,
    *,
    from_day: date | None = None,
    to_day: date | None = None,
    category_id: str | None = None,
    account_id: str | None = None,
    type_: TxnType | None = None,
    q: str | None = None,
    limit: int = 100,
    cursor: str | None = None,
) -> tuple[list[Txn], str | None]:
    """Newest-first keyset pagination. Day bounds are IST days: from_day inclusive,
    to_day exclusive."""
    stmt = select(Txn).order_by(Txn.at.desc(), Txn.id.desc())
    if from_day is not None:
        stmt = stmt.where(Txn.at >= ist_day_start(from_day))
    if to_day is not None:
        stmt = stmt.where(Txn.at < ist_day_start(to_day))
    if category_id is not None:
        stmt = stmt.where(Txn.category_id == category_id)
    if account_id is not None:
        stmt = stmt.where(or_(Txn.account_id == account_id, Txn.to_account_id == account_id))
    if type_ is not None:
        stmt = stmt.where(Txn.type == type_)
    if q:
        pattern = f"%{q}%"
        stmt = stmt.where(or_(Txn.title.ilike(pattern), Txn.note.ilike(pattern)))
    if cursor is not None:
        c_at, c_id = decode_cursor(cursor)
        stmt = stmt.where(or_(Txn.at < c_at, and_(Txn.at == c_at, Txn.id < c_id)))
    rows = list(session.scalars(stmt.limit(limit + 1)))
    next_cursor = None
    if len(rows) > limit:
        rows = rows[:limit]
        next_cursor = encode_cursor(rows[-1].at, rows[-1].id)
    return rows, next_cursor


def spent_between(session: Session, start: datetime, end: datetime) -> Paise:
    """Expense total in [start, end) — the number behind 'spent so far' heroes."""
    stmt = select(func.coalesce(func.sum(Txn.amount_paise), 0)).where(
        Txn.type == TxnType.EXPENSE, Txn.at >= start, Txn.at < end
    )
    return session.scalar(stmt) or 0


def suggest_titles(session: Session, q: str, *, limit: int = 6) -> list[TitleSuggestion]:
    """Latest use of each matching title, carrying its category/account memory."""
    stmt = (
        select(Txn.title, Txn.category_id, Txn.account_id)
        .where(Txn.title.ilike(f"{q}%"))
        .order_by(Txn.at.desc())
        .limit(60)
    )
    seen: set[str] = set()
    out: list[TitleSuggestion] = []
    for title, category_id, account_id in session.execute(stmt):
        key = title.lower()
        if key in seen:
            continue
        seen.add(key)
        out.append(TitleSuggestion(title=title, category_id=category_id, account_id=account_id))
        if len(out) >= limit:
            break
    return out


# --- pinned (one-tap repeats) -------------------------------------------------


def list_pinned(session: Session) -> list[Pinned]:
    return list(session.scalars(select(Pinned).order_by(Pinned.sort_order, Pinned.created_at)))


def upsert_pinned(session: Session, pinned_id: str, data: PinnedIn) -> Pinned:
    pinned_id = require_uuid(pinned_id)
    _require_account(session, data.account_id)
    if session.get(Category, data.category_id) is None:
        raise Invalid(f"no category {data.category_id}")
    row = session.get(Pinned, pinned_id)
    if row is None:
        row = Pinned(id=pinned_id)
        session.add(row)
    row.title = data.title
    row.amount_paise = data.amount_paise
    row.category_id = data.category_id
    row.account_id = data.account_id
    row.sort_order = data.sort_order
    session.commit()
    return row


def delete_pinned(session: Session, pinned_id: str) -> None:
    row = session.get(Pinned, pinned_id)
    if row is None:
        raise NotFound(f"no pinned {pinned_id}")
    session.delete(row)
    session.commit()


def stamp_pinned(session: Session, pinned_id: str, at: datetime | None = None) -> Txn:
    """One tap on Today: mint an expense txn from the pinned template."""
    row = session.get(Pinned, pinned_id)
    if row is None:
        raise NotFound(f"no pinned {pinned_id}")
    data = TxnIn(
        amount_paise=row.amount_paise,
        type=TxnType.EXPENSE,
        account_id=row.account_id,
        category_id=row.category_id,
        title=row.title,
        at=at or now_utc(),
    )
    txn, _ = upsert(session, new_id(), data)
    return txn


# --- day seals ----------------------------------------------------------------


def seal_day(session: Session, day: date) -> DaySeal:
    """Idempotent: sealing an already-sealed day returns the existing seal."""
    row = session.get(DaySeal, day)
    if row is None:
        row = DaySeal(date=day, sealed_at=now_utc())
        session.add(row)
        session.commit()
    return row


def seals_between(session: Session, from_day: date, to_day: date) -> list[DaySeal]:
    stmt = (
        select(DaySeal)
        .where(DaySeal.date >= from_day, DaySeal.date < to_day)
        .order_by(DaySeal.date)
    )
    return list(session.scalars(stmt))


def is_sealed(session: Session, day: date) -> bool:
    return session.get(DaySeal, day) is not None
