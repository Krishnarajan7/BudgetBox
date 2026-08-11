"""Ledger write path. Port of TxnRepo semantics: every mutation logs an Activity
snapshot in the same transaction, and undo replays the inverse. Balances are never
written — they derive from anchors + this ledger (see accounts.service)."""

import json
from datetime import date, datetime, timedelta

from sqlalchemy import and_, func, or_, select
from sqlalchemy.orm import Session

from budgetbox.api.pagination import decode_cursor, encode_cursor
from budgetbox.core.errors import Conflict, Invalid, NotFound
from budgetbox.core.ids import new_id, require_uuid
from budgetbox.core.money import Paise
from budgetbox.core.time import day_key, ist_day_start, now_utc, today_ist
from budgetbox.domain.insights import streak_days
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
    ActivityOut,
    CategoryUse,
    PinnedBoard,
    PinnedIn,
    PinnedOut,
    PinnedSuggestion,
    PinnedUse,
    RecentAmount,
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
    session: Session,
    txn_id: str,
    data: TxnIn,
    *,
    recurring_id: str | None = None,
    commit: bool = True,
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
        if commit:
            session.commit()
        return row, True

    if all(getattr(row, f) == getattr(data, f) for f in _TXN_FIELDS):
        return row, False  # idempotent retry
    before = _snapshot(row)
    for field in _TXN_FIELDS:
        setattr(row, field, getattr(data, field))
    _validate_shape(session, row)
    _log(session, txn_id, ActivityAction.EDITED, before)
    if commit:
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


def recent_activities(
    session: Session, *, limit: int = 20, txn_id: str | None = None
) -> list[Activity]:
    stmt = select(Activity).order_by(Activity.at.desc(), Activity.id.desc()).limit(limit)
    if txn_id is not None:
        stmt = stmt.where(Activity.txn_id == txn_id)
    return list(session.scalars(stmt))


def activity_out(session: Session, row: Activity) -> ActivityOut:
    """The log line the activity page draws: the snapshot's own words and figure,
    plus whether replaying the inverse would actually work right now."""
    try:
        snapshot = TxnOut.model_validate(json.loads(row.snapshot)["txn"])
    except (ValueError, KeyError):  # a snapshot from an older schema: still a line
        return ActivityOut(
            id=row.id,
            txn_id=row.txn_id,
            action=row.action,
            at=row.at,
            title=None,
            amount_paise=None,
            txn_type=None,
            undoable=False,
        )
    exists = session.get(Txn, row.txn_id) is not None
    match row.action:
        case ActivityAction.CREATED:
            undoable = exists
        case ActivityAction.EDITED:
            undoable = exists
        case ActivityAction.DELETED:
            undoable = not exists
    return ActivityOut(
        id=row.id,
        txn_id=row.txn_id,
        action=row.action,
        at=row.at,
        title=snapshot.title,
        amount_paise=snapshot.amount_paise,
        txn_type=snapshot.type,
        undoable=undoable,
    )


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
    """Latest use of each matching title, carrying its category/account memory.
    Substring, not prefix: typing 'sar' has to find 'Hotel Saravana', which is how
    the add sheet's ghost row behaves."""
    stmt = (
        select(Txn.title, Txn.category_id, Txn.account_id)
        .where(Txn.title.ilike(f"%{q}%"))
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


def recent_amounts(session: Session, category_id: str, *, limit: int = 3) -> list[RecentAmount]:
    """'usually ₹40' — the amounts this category is most often written for, over its
    last 60 entries. Ranked by how often, ties to the more recent figure."""
    stmt = (
        select(Txn.amount_paise)
        .where(Txn.type == TxnType.EXPENSE, Txn.category_id == category_id)
        .order_by(Txn.at.desc())
        .limit(60)
    )
    counts: dict[Paise, int] = {}
    first_seen: dict[Paise, int] = {}
    for index, (amount,) in enumerate(session.execute(stmt)):
        counts[amount] = counts.get(amount, 0) + 1
        first_seen.setdefault(amount, index)
    ranked = sorted(counts, key=lambda a: (-counts[a], first_seen[a]))
    return [RecentAmount(amount_paise=a, count=counts[a]) for a in ranked[:limit]]


def top_category_ids(session: Session, *, days: int = 90, limit: int = 5) -> list[CategoryUse]:
    """His most-written expense categories, most frequent first — the add sheet's
    chips. A window, not all time: the book follows what he does now."""
    since = ist_day_start(today_ist() - timedelta(days=days))
    stmt = (
        select(Txn.category_id, func.count(Txn.id))
        .where(Txn.type == TxnType.EXPENSE, Txn.category_id.is_not(None), Txn.at >= since)
        .group_by(Txn.category_id)
        .order_by(func.count(Txn.id).desc(), Txn.category_id)
        .limit(limit)
    )
    return [
        CategoryUse(category_id=cid, count=count)
        for cid, count in session.execute(stmt)
        if cid is not None
    ]


def money_by_day(session: Session, from_day: date, to_day: date) -> dict[date, tuple[Paise, Paise]]:
    """(spent, earned) per IST day inside [from_day, to_day). Transfers move money
    between his own pockets, so they are neither."""
    stmt = select(Txn.at, Txn.type, Txn.amount_paise).where(
        Txn.at >= ist_day_start(from_day),
        Txn.at < ist_day_start(to_day),
        Txn.type != TxnType.TRANSFER,
    )
    out: dict[date, tuple[Paise, Paise]] = {}
    for at, type_, amount in session.execute(stmt):
        day = day_key(at)
        spent, earned = out.get(day, (0, 0))
        if type_ is TxnType.EXPENSE:
            out[day] = (spent + amount, earned)
        else:
            out[day] = (spent, earned + amount)
    return out


def quiet_days(session: Session, *, today: date, lookback: int = 7) -> list[date]:
    """Days in the last week with nothing written down, most recent first. Today is
    never quiet — the day isn't over."""
    start = today - timedelta(days=lookback)
    spent_on = {day for day, (spent, _) in money_by_day(session, start, today).items() if spent > 0}
    return [d for i in range(1, lookback + 1) if (d := today - timedelta(days=i)) not in spent_on]


def largest_income_day(session: Session, from_day: date, to_day: date) -> int | None:
    """Day-of-month the biggest paycheque landed on — what the plans page calls
    salary day when nothing was configured."""
    stmt = (
        select(Txn.at)
        .where(
            Txn.type == TxnType.INCOME,
            Txn.at >= ist_day_start(from_day),
            Txn.at < ist_day_start(to_day),
        )
        .order_by(Txn.amount_paise.desc(), Txn.at)
        .limit(1)
    )
    at = session.scalar(stmt)
    return None if at is None else day_key(at).day


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


def _use_key(title: str, amount_paise: Paise) -> tuple[str, Paise]:
    return title.strip().lower(), amount_paise


def pinned_board(
    session: Session, *, today: date, window_days: int = 90, min_repeats: int = 3, limit: int = 3
) -> PinnedBoard:
    """The pinned manager in one call: every pin with how often it has actually been
    stamped, plus repeats that have earned a pin and don't have one."""
    pins = list_pinned(session)

    counts: dict[tuple[str, Paise], int] = {}
    last_at: dict[tuple[str, Paise], datetime] = {}
    rows = session.execute(
        select(Txn.title, Txn.amount_paise, Txn.at).where(Txn.type == TxnType.EXPENSE)
    )
    for title, amount, at in rows:
        key = _use_key(title, amount)
        counts[key] = counts.get(key, 0) + 1
        if key not in last_at or at > last_at[key]:
            last_at[key] = at

    items = [
        PinnedUse(
            pinned=PinnedOut.model_validate(p),
            use_count=counts.get(_use_key(p.title, p.amount_paise), 0),
            last_used_at=last_at.get(_use_key(p.title, p.amount_paise)),
        )
        for p in pins
    ]

    pinned_titles = {p.title.strip().lower() for p in pins}
    since = ist_day_start(today - timedelta(days=window_days))
    repeats = session.execute(
        select(Txn.title, func.count(Txn.id))
        .where(
            Txn.type == TxnType.EXPENSE,
            Txn.category_id.is_not(None),
            Txn.at >= since,
        )
        .group_by(Txn.title)
        .having(func.count(Txn.id) >= min_repeats)
        .order_by(func.count(Txn.id).desc(), Txn.title)
        .limit(12)
    )
    suggestions: list[PinnedSuggestion] = []
    for title, count in repeats:
        if title.strip().lower() in pinned_titles:
            continue
        latest = session.scalars(
            select(Txn)
            .where(Txn.title == title, Txn.category_id.is_not(None))
            .order_by(Txn.at.desc())
            .limit(1)
        ).first()
        if latest is None or latest.category_id is None:
            continue
        suggestions.append(
            PinnedSuggestion(
                title=latest.title,
                amount_paise=latest.amount_paise,
                category_id=latest.category_id,
                account_id=latest.account_id,
                count=count,
            )
        )
        if len(suggestions) >= limit:
            break
    return PinnedBoard(items=items, suggestions=suggestions)


# --- day seals ----------------------------------------------------------------


def seal_day(session: Session, day: date) -> DaySeal:
    """Idempotent: sealing an already-sealed day returns the existing seal."""
    row = session.get(DaySeal, day)
    if row is None:
        row = DaySeal(date=day, sealed_at=now_utc())
        session.add(row)
        session.commit()
    return row


def unseal_day(session: Session, day: date) -> None:
    """Reopen a closed page. Idempotent, and it leaves no scar: sealing is a ritual,
    not a ledger fact, so there is nothing to keep once he takes it back."""
    row = session.get(DaySeal, day)
    if row is not None:
        session.delete(row)
        session.commit()


def seal_streak_days(session: Session, today: date) -> int:
    """Evenings closed in a row, counting back from today (or yesterday, when today
    isn't sealed yet)."""
    sealed = set(session.scalars(select(DaySeal.date)))
    return streak_days(sealed, today)


def seals_between(session: Session, from_day: date, to_day: date) -> list[DaySeal]:
    stmt = (
        select(DaySeal)
        .where(DaySeal.date >= from_day, DaySeal.date < to_day)
        .order_by(DaySeal.date)
    )
    return list(session.scalars(stmt))


def is_sealed(session: Session, day: date) -> bool:
    return session.get(DaySeal, day) is not None
