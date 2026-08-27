"""The folio's rules.

Money in is a transfer, never an expense. Worth is units times the latest NAV.
And the daily job writes a balance anchor on the funds account so the net
worth chart shows what the market did — the ledger alone would only ever show
what was paid in."""

import datetime as dt
from decimal import Decimal

import structlog
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from budgetbox.core.errors import Conflict, Invalid, NotFound
from budgetbox.core.ids import new_id, require_uuid
from budgetbox.core.time import day_key, ist_day_start, now_utc, today_ist
from budgetbox.modules.accounts.models import Account, AccountKind, BalanceAnchor
from budgetbox.modules.folio import amfi
from budgetbox.modules.folio.models import (
    BUY_KINDS,
    KIND_SIGN,
    FolioEntry,
    FolioEntryKind,
    Fund,
)
from budgetbox.modules.folio.schemas import (
    ContributeIn,
    EntryOut,
    FolioPoint,
    FundIn,
    FundOut,
    FundPatch,
    OverviewOut,
    RedeemIn,
    SchemeOut,
    ValueIn,
)
from budgetbox.modules.transactions import service as txn_service
from budgetbox.modules.transactions.models import Txn, TxnType
from budgetbox.modules.transactions.schemas import TxnIn

log = structlog.get_logger()

#: The account the setup ritual already creates for money kept aside. The
#: folio adopts it rather than opening a rival beside it.
FOLIO_ACCOUNT_NAME = "SIP / mutual funds"

_PAISE = Decimal(100)


def folio_account(session: Session) -> Account:
    row = session.scalar(
        select(Account).where(Account.name == FOLIO_ACCOUNT_NAME, Account.kind == AccountKind.ASSET)
    )
    if row is None:
        row = Account(
            id=new_id(),
            name=FOLIO_ACCOUNT_NAME,
            kind=AccountKind.ASSET,
            sort_order=800,
        )
        session.add(row)
        session.flush()
    return row


# ————— schemes —————


def search_schemes(query: str, limit: int) -> list[SchemeOut]:
    """Straight to AMFI. Eighteen thousand rows is a two-second download and
    this is used a handful of times in a lifetime — caching it would be
    machinery guarding nothing."""
    schemes = amfi.search(amfi.fetch(), query, limit)
    return [SchemeOut(code=s.code, label=s.label, nav=s.nav, nav_date=s.nav_date) for s in schemes]


# ————— funds —————


def get_fund(session: Session, fund_id: str) -> Fund:
    row = session.get(Fund, fund_id)
    if row is None:
        raise NotFound(f"no fund {fund_id}")
    return row


def upsert_fund(session: Session, fund_id: str, data: FundIn) -> Fund:
    fund_id = require_uuid(fund_id)
    row = session.get(Fund, fund_id)
    if row is None:
        row = Fund(id=fund_id)
        session.add(row)
    row.name = data.name
    row.note = data.note
    if data.scheme_code != row.scheme_code:
        row.scheme_code = data.scheme_code
        # A fund that just learned its scheme should not keep yesterday's
        # hand-typed worth beside a real price.
        row.nav = None
        row.nav_date = None
    session.commit()
    if row.scheme_code:
        try:
            refresh_navs(session)
        except amfi.AmfiError:
            log.warning("amfi_refresh_failed_on_add", fund=row.id)
    return row


def patch_fund(session: Session, fund_id: str, data: FundPatch) -> Fund:
    row = get_fund(session, fund_id)
    for key, value in data.model_dump(exclude_unset=True).items():
        setattr(row, key, value)
    session.commit()
    return row


def delete_fund(session: Session, fund_id: str) -> None:
    row = get_fund(session, fund_id)
    held = session.scalar(
        select(func.count()).select_from(FolioEntry).where(FolioEntry.fund_id == row.id)
    )
    if held:
        raise Conflict("This fund has money in it — archive it instead of deleting it.")
    session.delete(row)
    session.commit()


# ————— money moving —————


def _require_account(session: Session, account_id: str) -> Account:
    row = session.get(Account, account_id)
    if row is None:
        raise Invalid(f"no account {account_id}")
    if row.name == FOLIO_ACCOUNT_NAME:
        raise Invalid("The funds account is not a pocket money can come from.")
    return row


def _units_for(
    fund: Fund, amount_paise: int, nav: float | None
) -> tuple[float | None, float | None]:
    price = nav if nav is not None else fund.nav
    if price is None or price <= 0:
        return None, None
    units = (Decimal(amount_paise) / _PAISE) / Decimal(str(price))
    return float(round(units, 5)), price


def _move(
    session: Session,
    fund: Fund,
    kind: FolioEntryKind,
    amount_paise: int,
    account_id: str,
    at: dt.datetime,
    note: str | None,
    nav: float | None,
) -> FolioEntry:
    pocket = _require_account(session, account_id)
    holding = folio_account(session)
    buying = KIND_SIGN[kind] > 0
    verb = "SIP" if kind is FolioEntryKind.SIP else ("Bought" if buying else "Redeemed")
    txn, _ = txn_service.upsert(
        session,
        new_id(),
        TxnIn(
            amount_paise=amount_paise,
            type=TxnType.TRANSFER,
            account_id=pocket.id if buying else holding.id,
            to_account_id=holding.id if buying else pocket.id,
            title=f"{verb} — {fund.name}",
            note=note,
            at=at,
        ),
        commit=False,
    )
    units, price = _units_for(fund, amount_paise, nav)
    entry = FolioEntry(
        id=new_id(),
        fund_id=fund.id,
        kind=kind,
        amount_paise=amount_paise,
        units=units,
        nav=price,
        at=at,
        note=note,
        txn_id=txn.id,
    )
    session.add(entry)
    return entry


def contribute(session: Session, fund_id: str, data: ContributeIn) -> EntryOut:
    fund = get_fund(session, fund_id)
    if data.kind is FolioEntryKind.REDEEM:
        raise Invalid("Use redeem to take money out.")
    entry = _move(
        session,
        fund,
        data.kind,
        data.amount_paise,
        data.account_id,
        data.at or now_utc(),
        data.note,
        data.nav,
    )
    session.commit()
    return EntryOut.model_validate(entry)


def redeem(session: Session, fund_id: str, data: RedeemIn) -> EntryOut:
    fund = get_fund(session, fund_id)
    held = _units(session, fund.id)
    entry = _move(
        session,
        fund,
        FolioEntryKind.REDEEM,
        data.amount_paise,
        data.account_id,
        data.at or now_utc(),
        data.note,
        data.nav,
    )
    if entry.units is not None and entry.units > held + 1e-6:
        session.rollback()
        raise Invalid("More units than the fund holds.")
    session.commit()
    return EntryOut.model_validate(entry)


def set_value(session: Session, fund_id: str, data: ValueIn) -> FundOut:
    """The hand-given worth, for a fund AMFI does not price."""
    fund = get_fund(session, fund_id)
    if fund.scheme_code:
        raise Conflict("This fund prices itself from AMFI.")
    fund.manual_value_paise = data.value_paise
    fund.manual_value_at = data.at or now_utc()
    session.commit()
    return fund_view(session, fund)


# ————— worth —————


def _units(session: Session, fund_id: str) -> float:
    rows = session.execute(
        select(FolioEntry.kind, FolioEntry.units).where(FolioEntry.fund_id == fund_id)
    )
    return sum(KIND_SIGN[kind] * float(units or 0) for kind, units in rows)


def refresh_navs(session: Session) -> int:
    """Pull AMFI once and price every scheme the book holds."""
    wanted = {
        code
        for (code,) in session.execute(
            select(Fund.scheme_code).where(Fund.scheme_code.is_not(None), Fund.archived.is_(False))
        )
        if code
    }
    if not wanted:
        return 0
    prices = {s.code: s for s in amfi.fetch() if s.code in wanted}
    touched = 0
    for fund in session.scalars(
        select(Fund).where(Fund.scheme_code.in_(wanted), Fund.archived.is_(False))
    ):
        quote = prices.get(fund.scheme_code or "")
        if quote is None:
            continue
        fund.nav = quote.nav
        fund.nav_date = quote.nav_date
        touched += 1
    session.commit()
    return touched


def _cost_and_units(session: Session, fund_id: str) -> tuple[int, float, int, int, int]:
    """(cost_paise, units, entry_count, sip_count, sip_paise). Redemptions
    reduce cost proportionally: taking out a third of the units takes a third
    of what was paid for them with it, so the gain figure stays honest."""
    rows = list(
        session.execute(
            select(FolioEntry.kind, FolioEntry.amount_paise, FolioEntry.units)
            .where(FolioEntry.fund_id == fund_id)
            .order_by(FolioEntry.at)
        )
    )
    cost = 0
    units = 0.0
    sip_count = 0
    sip_paise = 0
    for kind, amount, entry_units in rows:
        u = float(entry_units or 0)
        if kind in BUY_KINDS:
            cost += amount
            units += u
            if kind is FolioEntryKind.SIP:
                sip_count += 1
                sip_paise += amount
        else:
            if units > 0 and u > 0:
                cost -= round(cost * min(u / units, 1.0))
            else:
                cost = max(0, cost - amount)
            units = max(0.0, units - u)
    return cost, units, len(rows), sip_count, sip_paise


def fund_view(session: Session, fund: Fund) -> FundOut:
    cost, units, count, sip_count, sip_paise = _cost_and_units(session, fund.id)
    priced = fund.scheme_code is not None and fund.nav is not None
    if priced:
        value = round(units * float(fund.nav or 0) * 100)
    elif fund.manual_value_paise is not None:
        value = fund.manual_value_paise
    else:
        # Nothing has priced it yet: what went in is the only honest figure.
        value = cost
    bounds = session.execute(
        select(func.min(FolioEntry.at), func.max(FolioEntry.at)).where(
            FolioEntry.fund_id == fund.id
        )
    ).one()
    return FundOut(
        id=fund.id,
        name=fund.name,
        scheme_code=fund.scheme_code,
        note=fund.note,
        archived=fund.archived,
        cost_paise=cost,
        value_paise=value,
        gain_paise=value - cost,
        return_ratio=((value - cost) / cost) if cost > 0 else None,
        units=round(units, 5),
        nav=fund.nav,
        nav_date=fund.nav_date,
        priced=priced,
        manual_value_at=fund.manual_value_at,
        entries=count,
        sip_count=sip_count,
        sip_paise=sip_paise,
        first_at=bounds[0],
        last_at=bounds[1],
    )


def funds(session: Session, *, include_archived: bool = False) -> list[FundOut]:
    stmt = select(Fund)
    if not include_archived:
        stmt = stmt.where(Fund.archived.is_(False))
    views = [fund_view(session, f) for f in session.scalars(stmt.order_by(Fund.sort_order))]
    views.sort(key=lambda v: (-v.value_paise, v.name.lower()))
    return views


def entries(session: Session, fund_id: str) -> list[EntryOut]:
    rows = session.scalars(
        select(FolioEntry).where(FolioEntry.fund_id == fund_id).order_by(FolioEntry.at.desc())
    )
    return [EntryOut.model_validate(r) for r in rows]


def overview(session: Session) -> OverviewOut:
    views = funds(session)
    cost = sum(v.cost_paise for v in views)
    value = sum(v.value_paise for v in views)
    month_start = ist_day_start(today_ist().replace(day=1))
    month = session.scalar(
        select(func.coalesce(func.sum(FolioEntry.amount_paise), 0)).where(
            FolioEntry.at >= month_start,
            FolioEntry.kind.in_(BUY_KINDS),
        )
    )
    priced_dates = [v.nav_date for v in views if v.nav_date is not None]
    return OverviewOut(
        cost_paise=cost,
        value_paise=value,
        gain_paise=value - cost,
        return_ratio=((value - cost) / cost) if cost > 0 else None,
        funds=len(views),
        month_paise=int(month or 0),
        priced_upto=min(priced_dates) if priced_dates else None,
        unpriced_funds=sum(1 for v in views if not v.priced),
    )


def series(session: Session, days: int) -> list[FolioPoint]:
    """The two lines. Cost is exact history — every entry, in order. Value is
    today's price applied to the units held on each past day: honest about
    *what was owned* and deliberately not a claim about what it was worth
    then, since AMFI's file only ever carries today."""
    start = today_ist() - dt.timedelta(days=days)
    rows = list(
        session.execute(
            select(
                FolioEntry.at,
                FolioEntry.kind,
                FolioEntry.amount_paise,
                FolioEntry.units,
                FolioEntry.fund_id,
            ).order_by(FolioEntry.at)
        )
    )
    if not rows:
        return []
    navs = {f.id: float(f.nav or 0) for f in session.scalars(select(Fund))}
    manual = {f.id: f for f in session.scalars(select(Fund))}
    points: list[FolioPoint] = []
    cost = 0
    units_by_fund: dict[str, float] = {}
    index = 0
    day = day_key(rows[0][0])
    last = today_ist()
    while day <= last:
        end = ist_day_start(day) + dt.timedelta(days=1)
        while index < len(rows) and rows[index][0] < end:
            _at, kind, amount, entry_units, fund_id = rows[index]
            u = float(entry_units or 0)
            held = units_by_fund.get(fund_id, 0.0)
            if kind in BUY_KINDS:
                cost += amount
                units_by_fund[fund_id] = held + u
            else:
                if held > 0 and u > 0:
                    cost -= round(cost * min(u / held, 1.0))
                else:
                    cost = max(0, cost - amount)
                units_by_fund[fund_id] = max(0.0, held - u)
            index += 1
        if day >= start:
            value = 0
            for fund_id, held in units_by_fund.items():
                nav = navs.get(fund_id, 0)
                if nav > 0:
                    value += round(held * nav * 100)
                else:
                    fund = manual.get(fund_id)
                    if fund is not None and fund.manual_value_paise is not None:
                        value += fund.manual_value_paise
            points.append(FolioPoint(date=day, cost_paise=cost, value_paise=value or cost))
        day += dt.timedelta(days=1)
    return points


def anchor_worth(session: Session) -> str:
    """Write today's market worth onto the funds account as a balance anchor.

    The ledger alone can only ever show what was paid in — a transfer records
    money moving, not the market moving. An anchor is the book's own word for
    'this is what it is actually worth as of now', which is exactly the claim
    AMFI lets us make. With it, the net worth chart grows the way the money
    really did."""
    views = funds(session)
    if not views:
        return "no funds"
    account = folio_account(session)
    worth = sum(v.value_paise for v in views)
    at = now_utc()
    today = day_key(at)
    existing = session.scalar(
        select(BalanceAnchor)
        .where(BalanceAnchor.account_id == account.id)
        .order_by(BalanceAnchor.at.desc())
        .limit(1)
    )
    # One anchor a day: today's replaces itself rather than stacking.
    if existing is not None and day_key(existing.at) == today:
        existing.at = at
        existing.balance_paise = worth
    else:
        session.add(BalanceAnchor(id=new_id(), account_id=account.id, at=at, balance_paise=worth))
    session.commit()
    return f"funds worth {worth} paise"


def adoptable(session: Session, limit: int) -> list[Txn]:
    """Expenses that were really contributions — the same backfill door the
    slate offers."""
    taken = select(FolioEntry.txn_id).where(FolioEntry.txn_id.is_not(None))
    holding = session.scalar(
        select(Account.id).where(
            Account.name == FOLIO_ACCOUNT_NAME, Account.kind == AccountKind.ASSET
        )
    )
    stmt = (
        select(Txn)
        .where(Txn.type == TxnType.EXPENSE, Txn.id.not_in(taken))
        .order_by(Txn.at.desc())
        .limit(limit)
    )
    if holding is not None:
        stmt = stmt.where(Txn.account_id != holding)
    return list(session.scalars(stmt))
