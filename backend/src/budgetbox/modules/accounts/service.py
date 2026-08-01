from datetime import datetime

from sqlalchemy import and_, case, func, or_, select
from sqlalchemy.orm import Session

from budgetbox.core.errors import NotFound
from budgetbox.core.ids import new_id, require_uuid
from budgetbox.core.money import Paise
from budgetbox.core.time import now_utc
from budgetbox.modules.accounts.models import Account, BalanceAnchor
from budgetbox.modules.accounts.schemas import AccountIn, AccountPatch, AnchorIn
from budgetbox.modules.transactions.models import Txn, TxnType


def get(session: Session, account_id: str) -> Account:
    row = session.get(Account, account_id)
    if row is None:
        raise NotFound(f"no account {account_id}")
    return row


def list_accounts(session: Session, *, include_archived: bool = False) -> list[Account]:
    stmt = select(Account).order_by(Account.sort_order, Account.name)
    if not include_archived:
        stmt = stmt.where(Account.archived.is_(False))
    return list(session.scalars(stmt))


def upsert(session: Session, account_id: str, data: AccountIn) -> Account:
    account_id = require_uuid(account_id)
    row = session.get(Account, account_id)
    if row is None:
        row = Account(id=account_id, kind=data.kind)
        session.add(row)
    row.name = data.name
    row.kind = data.kind
    row.sort_order = data.sort_order
    session.commit()
    return row


def patch(session: Session, account_id: str, data: AccountPatch) -> Account:
    row = get(session, account_id)
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(row, field, value)
    session.commit()
    return row


def add_anchor(session: Session, account_id: str, data: AnchorIn) -> BalanceAnchor:
    get(session, account_id)
    anchor = BalanceAnchor(
        id=new_id(),
        account_id=account_id,
        at=data.at or now_utc(),
        balance_paise=data.balance_paise,
    )
    session.add(anchor)
    session.commit()
    return anchor


def balance_as_of(
    session: Session, account_id: str, at: datetime | None = None
) -> tuple[Paise, datetime | None]:
    """Balance = latest anchor at-or-before the cutoff, plus signed ledger deltas
    after it. Returns (balance, anchor time); anchor time is the as-of staleness cue.
    Exact for any past instant, which is what makes snapshot backfill possible."""
    cutoff = at or now_utc()

    anchor_stmt = (
        select(BalanceAnchor)
        .where(BalanceAnchor.account_id == account_id, BalanceAnchor.at <= cutoff)
        .order_by(BalanceAnchor.at.desc())
        .limit(1)
    )
    anchor = session.scalar(anchor_stmt)
    base: Paise = anchor.balance_paise if anchor else 0
    since = anchor.at if anchor else None

    signed = case(
        (and_(Txn.account_id == account_id, Txn.type == TxnType.EXPENSE), -Txn.amount_paise),
        (and_(Txn.account_id == account_id, Txn.type == TxnType.INCOME), Txn.amount_paise),
        (and_(Txn.account_id == account_id, Txn.type == TxnType.TRANSFER), -Txn.amount_paise),
        (Txn.to_account_id == account_id, Txn.amount_paise),
        else_=0,
    )
    delta_stmt = select(func.coalesce(func.sum(signed), 0)).where(
        or_(Txn.account_id == account_id, Txn.to_account_id == account_id),
        Txn.at <= cutoff,
    )
    if since is not None:
        delta_stmt = delta_stmt.where(Txn.at > since)
    delta = session.scalar(delta_stmt) or 0
    return base + delta, since
