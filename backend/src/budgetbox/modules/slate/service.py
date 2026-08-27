"""The slate's rules.

Every movement of real money goes through the ledger as a transfer between a
real pocket and one asset account, 'On the slate'. Nothing here writes a
balance: balances derive, exactly as they do for accounts.
"""

import datetime as dt

from sqlalchemy import Select, func, select
from sqlalchemy.orm import Session

from budgetbox.core.errors import Conflict, Invalid, NotFound
from budgetbox.core.ids import new_id, require_uuid
from budgetbox.core.time import now_utc
from budgetbox.modules.accounts.models import Account, AccountKind
from budgetbox.modules.slate.models import (
    CLOSING_KINDS,
    KIND_SIGN,
    SlateEntry,
    SlateKind,
    SlatePerson,
)
from budgetbox.modules.slate.schemas import (
    AdoptableOut,
    AdoptIn,
    CloseIn,
    EntryOut,
    LendIn,
    OverviewOut,
    PersonIn,
    PersonOut,
    PersonPatch,
    RepayIn,
)
from budgetbox.modules.transactions import service as txn_service
from budgetbox.modules.transactions.models import Txn, TxnType
from budgetbox.modules.transactions.schemas import TxnIn

#: The one account the slate adds. Created on first use, never by the setup
#: ritual — a book that never lends never grows the row.
SLATE_ACCOUNT_NAME = "On the slate"


def slate_account(session: Session) -> Account:
    row = session.scalar(
        select(Account).where(Account.name == SLATE_ACCOUNT_NAME, Account.kind == AccountKind.ASSET)
    )
    if row is None:
        row = Account(
            id=new_id(),
            name=SLATE_ACCOUNT_NAME,
            kind=AccountKind.ASSET,
            # Last in the list: it is a holding pot, not a pocket to spend from.
            sort_order=900,
        )
        session.add(row)
        session.flush()
    return row


# ————— people —————


def get_person(session: Session, person_id: str) -> SlatePerson:
    row = session.get(SlatePerson, person_id)
    if row is None:
        raise NotFound(f"no person {person_id}")
    return row


def upsert_person(session: Session, person_id: str, data: PersonIn) -> SlatePerson:
    person_id = require_uuid(person_id)
    row = session.get(SlatePerson, person_id)
    if row is None:
        row = SlatePerson(id=person_id)
        session.add(row)
    row.name = data.name
    row.relation = data.relation
    row.note = data.note
    session.commit()
    return row


def patch_person(session: Session, person_id: str, data: PersonPatch) -> SlatePerson:
    row = get_person(session, person_id)
    fields = data.model_dump(exclude_unset=True)
    for key, value in fields.items():
        setattr(row, key, value)
    session.commit()
    return row


def delete_person(session: Session, person_id: str) -> None:
    """Only a clean, empty slate can be removed. A person with history is
    archived instead — the book does not forget money that moved."""
    row = get_person(session, person_id)
    count = session.scalar(
        select(func.count()).select_from(SlateEntry).where(SlateEntry.person_id == row.id)
    )
    if count:
        raise Conflict("This slate has history — archive it instead of deleting it.")
    session.delete(row)
    session.commit()


# ————— movements —————


def _require_account(session: Session, account_id: str) -> Account:
    row = session.get(Account, account_id)
    if row is None:
        raise Invalid(f"no account {account_id}")
    if row.name == SLATE_ACCOUNT_NAME:
        raise Invalid("The slate account is not a pocket money can come from.")
    return row


def _write(
    session: Session,
    person: SlatePerson,
    kind: SlateKind,
    amount_paise: int,
    at: dt.datetime,
    note: str | None,
    txn_id: str | None,
) -> SlateEntry:
    entry = SlateEntry(
        id=new_id(),
        person_id=person.id,
        kind=kind,
        amount_paise=amount_paise,
        at=at,
        note=note,
        txn_id=txn_id,
    )
    session.add(entry)
    return entry


def _move(
    session: Session,
    person: SlatePerson,
    kind: SlateKind,
    amount_paise: int,
    account_id: str,
    at: dt.datetime,
    note: str | None,
) -> SlateEntry:
    """The money half: a transfer between a real pocket and the slate account.
    Direction follows the kind — out of pocket when the balance grows, back
    into pocket when it shrinks."""
    pocket = _require_account(session, account_id)
    slate = slate_account(session)
    towards_slate = KIND_SIGN[kind] > 0
    verb = {
        SlateKind.LENT: "Lent",
        SlateKind.REPAID: "Repaid by",
        SlateKind.BORROWED: "Borrowed from",
        SlateKind.SETTLED: "Settled with",
    }[kind]
    txn, _ = txn_service.upsert(
        session,
        new_id(),
        TxnIn(
            amount_paise=amount_paise,
            type=TxnType.TRANSFER,
            account_id=pocket.id if towards_slate else slate.id,
            to_account_id=slate.id if towards_slate else pocket.id,
            title=f"{verb} {person.name}",
            note=note,
            at=at,
        ),
        commit=False,
    )
    return _write(session, person, kind, amount_paise, at, note, txn.id)


def lend(session: Session, person_id: str, data: LendIn) -> EntryOut:
    person = get_person(session, person_id)
    entry = _move(
        session,
        person,
        SlateKind.LENT,
        data.amount_paise,
        data.account_id,
        data.at or now_utc(),
        data.note,
    )
    session.commit()
    return EntryOut.model_validate(entry)


def borrow(session: Session, person_id: str, data: LendIn) -> EntryOut:
    person = get_person(session, person_id)
    entry = _move(
        session,
        person,
        SlateKind.BORROWED,
        data.amount_paise,
        data.account_id,
        data.at or now_utc(),
        data.note,
    )
    session.commit()
    return EntryOut.model_validate(entry)


def repay(session: Session, person_id: str, data: RepayIn) -> EntryOut:
    """Money coming back. Overpaying is allowed and simply tips the slate the
    other way — that is what actually happens when someone rounds up."""
    person = get_person(session, person_id)
    kind = SlateKind.REPAID if balance(session, person.id) >= 0 else SlateKind.SETTLED
    entry = _move(
        session,
        person,
        kind,
        data.amount_paise,
        data.account_id,
        data.at or now_utc(),
        data.note,
    )
    session.commit()
    return EntryOut.model_validate(entry)


def close(session: Session, person_id: str, data: CloseIn) -> EntryOut:
    """Let it go. Only now does a loan become an expense — dated the day the
    decision was made, not the day the money left."""
    person = get_person(session, person_id)
    standing = balance(session, person.id)
    if standing == 0:
        raise Conflict("This slate is already clean.")
    amount = data.amount_paise or abs(standing)
    if amount > abs(standing):
        raise Invalid("More than the standing balance.")
    kind = SlateKind.FORGIVEN if standing > 0 else SlateKind.WRITTEN_OFF
    at = data.at or now_utc()
    slate = slate_account(session)
    txn, _ = txn_service.upsert(
        session,
        new_id(),
        TxnIn(
            amount_paise=amount,
            # Forgiven: the money finally leaves for good. Written off: money
            # that was never yours becomes yours.
            type=TxnType.EXPENSE if kind is SlateKind.FORGIVEN else TxnType.INCOME,
            account_id=slate.id,
            title=("Let go — " if kind is SlateKind.FORGIVEN else "Written off — ") + person.name,
            note=data.note,
            at=at,
        ),
        commit=False,
    )
    entry = _write(session, person, kind, amount, at, data.note, txn.id)
    session.commit()
    return EntryOut.model_validate(entry)


def adopt(session: Session, person_id: str, data: AdoptIn) -> EntryOut:
    """An expense already in the book that was really a loan: convert it into
    a transfer onto the slate instead of writing a second line beside it.
    Nothing is double counted, and that month's spending gets more honest."""
    person = get_person(session, person_id)
    txn = session.get(Txn, data.txn_id)
    if txn is None:
        raise NotFound(f"no txn {data.txn_id}")
    # Order matters: a line already taken has *become* a transfer, so the
    # type check below would otherwise answer a clear question confusingly.
    existing = session.scalar(select(SlateEntry).where(SlateEntry.txn_id == txn.id))
    if existing is not None:
        raise Conflict("That entry is already on a slate.")
    if txn.type is not TxnType.EXPENSE:
        raise Invalid("Only an expense can move onto the slate.")
    slate = slate_account(session)
    if txn.account_id == slate.id:
        raise Invalid("That line already belongs to the slate.")
    txn_service.upsert(
        session,
        txn.id,
        TxnIn(
            amount_paise=txn.amount_paise,
            type=TxnType.TRANSFER,
            account_id=txn.account_id,
            to_account_id=slate.id,
            title=f"Lent {person.name}",
            note=txn.note,
            at=txn.at,
        ),
        commit=False,
    )
    entry = _write(session, person, SlateKind.LENT, txn.amount_paise, txn.at, txn.note, txn.id)
    session.commit()
    return EntryOut.model_validate(entry)


def adoptable(session: Session, limit: int) -> list[AdoptableOut]:
    """Recent expenses not already on a slate — the pool the 'already in the
    book' door offers. Newest first; the phone does the searching."""
    taken = select(SlateEntry.txn_id).where(SlateEntry.txn_id.is_not(None))
    slate = session.scalar(
        select(Account.id).where(
            Account.name == SLATE_ACCOUNT_NAME, Account.kind == AccountKind.ASSET
        )
    )
    stmt = (
        select(Txn)
        .where(Txn.type == TxnType.EXPENSE, Txn.id.not_in(taken))
        .order_by(Txn.at.desc())
        .limit(limit)
    )
    if slate is not None:
        stmt = stmt.where(Txn.account_id != slate)
    return [
        AdoptableOut(
            txn_id=t.id,
            title=t.title,
            amount_paise=t.amount_paise,
            at=t.at,
            account_id=t.account_id,
            category=None,
        )
        for t in session.scalars(stmt)
    ]


# ————— reading —————


def _signed_sum(stmt: Select[tuple[SlateKind, int]], session: Session) -> int:
    return sum(KIND_SIGN[kind] * amount for kind, amount in session.execute(stmt))


def balance(session: Session, person_id: str) -> int:
    """Positive: they owe you. Negative: you owe them."""
    return _signed_sum(
        select(SlateEntry.kind, SlateEntry.amount_paise).where(SlateEntry.person_id == person_id),
        session,
    )


def entries(session: Session, person_id: str) -> list[EntryOut]:
    rows = session.scalars(
        select(SlateEntry).where(SlateEntry.person_id == person_id).order_by(SlateEntry.at.desc())
    )
    return [EntryOut.model_validate(r) for r in rows]


def _person_view(session: Session, person: SlatePerson) -> PersonOut:
    rows = list(
        session.execute(
            select(SlateEntry.kind, SlateEntry.amount_paise, SlateEntry.at)
            .where(SlateEntry.person_id == person.id)
            .order_by(SlateEntry.at)
        )
    )
    running = 0
    lent = 0
    returned = 0
    loops_total = 0
    loops_closed = 0
    outstanding_since: dt.datetime | None = None
    for kind, amount, at in rows:
        was_clean = running == 0
        if kind in (SlateKind.LENT, SlateKind.BORROWED):
            if kind is SlateKind.LENT:
                lent += amount
            if was_clean:
                loops_total += 1
                outstanding_since = at
        if kind is SlateKind.REPAID:
            returned += amount
        running += KIND_SIGN[kind] * amount
        if running == 0 and not was_clean:
            outstanding_since = None
            # A loop that ended by being paid back counts as returned; one
            # that ended by being let go does not.
            if kind not in CLOSING_KINDS:
                loops_closed += 1
    return PersonOut(
        id=person.id,
        name=person.name,
        relation=person.relation,
        note=person.note,
        archived=person.archived,
        balance_paise=running,
        lent_paise=lent,
        returned_paise=returned,
        entries=len(rows),
        loops_closed=loops_closed,
        loops_total=loops_total,
        since=rows[0][2] if rows else None,
        last_at=rows[-1][2] if rows else None,
        outstanding_since=outstanding_since,
    )


def people(session: Session, *, include_archived: bool = False) -> list[PersonOut]:
    """Owed-to-you first and largest first; clean slates sink to the bottom."""
    stmt = select(SlatePerson)
    if not include_archived:
        stmt = stmt.where(SlatePerson.archived.is_(False))
    views = [_person_view(session, p) for p in session.scalars(stmt)]
    views.sort(key=lambda v: (v.balance_paise == 0, -v.balance_paise, v.name.lower()))
    return views


def person_view(session: Session, person_id: str) -> PersonOut:
    return _person_view(session, get_person(session, person_id))


def overview(session: Session) -> OverviewOut:
    views = people(session, include_archived=True)
    owed = sum(v.balance_paise for v in views if v.balance_paise > 0)
    owing = -sum(v.balance_paise for v in views if v.balance_paise < 0)
    net = owed - owing
    account = session.scalar(
        select(Account).where(Account.name == SLATE_ACCOUNT_NAME, Account.kind == AccountKind.ASSET)
    )
    held = 0 if account is None else _account_balance(session, account.id)
    return OverviewOut(
        owed_to_you_paise=owed,
        you_owe_paise=owing,
        net_paise=net,
        people_in_debt=sum(1 for v in views if v.balance_paise > 0),
        people_you_owe=sum(1 for v in views if v.balance_paise < 0),
        slate_account_paise=held,
        balanced=held == net,
    )


def _account_balance(session: Session, account_id: str) -> int:
    """What the ledger says is parked on the slate. Derived, like every other
    balance in the book: money in, minus money out."""
    incoming = session.scalar(
        select(func.coalesce(func.sum(Txn.amount_paise), 0)).where(Txn.to_account_id == account_id)
    )
    outgoing = session.scalar(
        select(func.coalesce(func.sum(Txn.amount_paise), 0)).where(Txn.account_id == account_id)
    )
    return int(incoming or 0) - int(outgoing or 0)
