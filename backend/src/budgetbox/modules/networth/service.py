import datetime as dt

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from budgetbox.core.money import Paise
from budgetbox.core.time import ist_day_start, today_ist
from budgetbox.domain.periods import fy_start
from budgetbox.modules.accounts import service as account_service
from budgetbox.modules.accounts.models import Account, AccountKind, BalanceAnchor
from budgetbox.modules.networth.models import AccountSnapshot
from budgetbox.modules.transactions.models import Txn

# What owning money vs owing money looks like.
_LIABILITY_KINDS = (AccountKind.CARD, AccountKind.LIABILITY)

# Recent days re-derived every run so backdated edits converge without a manual
# rebuild; anything older is assumed settled (full rebuild stays available).
_REFRESH_DAYS = 90


def _sign(kind: AccountKind) -> int:
    return -1 if kind in _LIABILITY_KINDS else 1


def _first_activity_day(session: Session, account_id: str) -> dt.date | None:
    """Earliest IST day this account has any truth for (anchor or txn)."""
    first_anchor = session.scalar(
        select(func.min(BalanceAnchor.at)).where(BalanceAnchor.account_id == account_id)
    )
    first_txn = session.scalar(
        select(func.min(Txn.at)).where(
            (Txn.account_id == account_id) | (Txn.to_account_id == account_id)
        )
    )
    instants = [i for i in (first_anchor, first_txn) if i is not None]
    if not instants:
        return None
    from budgetbox.core.time import day_key

    return day_key(min(instants))


def snapshot_account(
    session: Session, account: Account, *, upto: dt.date, rebuild_from: dt.date | None = None
) -> int:
    """Upsert end-of-day balances for every missing day (and re-derive the recent
    refresh window). Returns rows written."""
    start = rebuild_from or _first_activity_day(session, account.id)
    if start is None:
        return 0
    refresh_floor = upto - dt.timedelta(days=_REFRESH_DAYS)
    existing = {
        s.date: s
        for s in session.scalars(
            select(AccountSnapshot).where(AccountSnapshot.account_id == account.id)
        )
    }
    written = 0
    day = start
    while day <= upto:
        if day not in existing or day >= refresh_floor:
            balance, _ = account_service.balance_as_of(
                session, account.id, at=ist_day_start(day + dt.timedelta(days=1))
            )
            row = existing.get(day)
            if row is None:
                session.add(AccountSnapshot(account_id=account.id, date=day, balance_paise=balance))
                written += 1
            elif row.balance_paise != balance:
                row.balance_paise = balance
                written += 1
        day += dt.timedelta(days=1)
    session.commit()
    return written


def snapshot_all(session: Session, *, upto: dt.date | None = None, rebuild: bool = False) -> int:
    upto = upto or today_ist()
    written = 0
    for account in session.scalars(select(Account)):
        rebuild_from = _first_activity_day(session, account.id) if rebuild else None
        written += snapshot_account(session, account, upto=upto, rebuild_from=rebuild_from)
    return written


def current(session: Session) -> tuple[Paise, Paise, Paise]:
    """(net_worth, assets, liabilities) right now, derived live."""
    assets = 0
    liabilities = 0
    for account in session.scalars(select(Account).where(Account.archived.is_(False))):
        balance, _ = account_service.balance_as_of(session, account.id)
        if _sign(account.kind) > 0:
            assets += balance
        else:
            liabilities += balance
    return assets - liabilities, assets, liabilities


def peak(points: list[tuple[dt.date, Paise]]) -> tuple[dt.date, Paise] | None:
    """The high-water mark of a series. Ties go to the earlier day — the first time
    he reached it is the one that counts."""
    best: tuple[dt.date, Paise] | None = None
    for day, value in points:
        if best is None or value > best[1]:
            best = (day, value)
    return best


def range_start(range_key: str, today: dt.date) -> dt.date | None:
    match range_key:
        case "1m":
            return today - dt.timedelta(days=30)
        case "6m":
            return today - dt.timedelta(days=182)
        case "fy":
            return fy_start(today)
        case _:  # "all"
            return None


def series(
    session: Session,
    *,
    start: dt.date | None,
    account_id: str | None = None,
    max_points: int = 120,
) -> list[tuple[dt.date, Paise]]:
    """Daily points from snapshots with per-account forward-fill (an account keeps
    its last known balance on days it has no row). account_id narrows to one
    account's raw balance (sparklines); otherwise it's signed net worth."""
    stmt = select(AccountSnapshot).order_by(AccountSnapshot.date)
    if start is not None:
        # Include the last pre-range row per account so forward-fill starts right.
        stmt = stmt.where(AccountSnapshot.date >= start - dt.timedelta(days=1))
    if account_id is not None:
        stmt = stmt.where(AccountSnapshot.account_id == account_id)
    rows = list(session.scalars(stmt))
    if not rows:
        return []

    signs: dict[str, int] = {a.id: _sign(a.kind) for a in session.scalars(select(Account))}
    by_day: dict[dt.date, dict[str, Paise]] = {}
    for row in rows:
        by_day.setdefault(row.date, {})[row.account_id] = row.balance_paise

    # Never invent leading zeros: the series starts where the data does.
    first_day = max(start, min(by_day)) if start is not None else min(by_day)
    last_day = max(max(by_day), first_day)
    held: dict[str, Paise] = {}
    points: list[tuple[dt.date, Paise]] = []
    day = min(min(by_day), first_day)
    while day <= last_day:
        for acct, balance in by_day.get(day, {}).items():
            held[acct] = balance
        if day >= first_day:
            if account_id is not None:
                total = held.get(account_id, 0)
            else:
                total = sum(signs.get(acct, 1) * bal for acct, bal in held.items())
            points.append((day, total))
        day += dt.timedelta(days=1)

    if len(points) > max_points:
        stride = -(-len(points) // max_points)  # ceil
        sampled = points[::stride]
        if sampled[-1] != points[-1]:
            sampled.append(points[-1])  # today always shown exactly
        points = sampled
    return points
