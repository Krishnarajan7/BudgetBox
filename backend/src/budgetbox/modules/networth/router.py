from datetime import date, datetime
from typing import Literal

from fastapi import APIRouter, Query

from budgetbox.api.deps import SessionDep
from budgetbox.api.schemas import APIModel, StrictPaise
from budgetbox.core.time import today_ist
from budgetbox.modules.accounts import service as account_service
from budgetbox.modules.accounts.models import AccountKind
from budgetbox.modules.networth import service

router = APIRouter(prefix="/networth", tags=["networth"])


class NetWorthNow(APIModel):
    net_worth_paise: StrictPaise
    assets_paise: StrictPaise
    liabilities_paise: StrictPaise
    day: date


class SeriesPoint(APIModel):
    date: date
    value_paise: StrictPaise


class SeriesOut(APIModel):
    range: str
    points: list[SeriesPoint]
    # Where the line started and how far it has travelled inside this range.
    first_paise: StrictPaise | None
    last_paise: StrictPaise | None
    delta_paise: StrictPaise
    # The high-water mark behind the dashed watermark: within the range, and the
    # true all-time one, so "highest it's ever been" actually means ever.
    peak_paise: StrictPaise | None
    peak_date: date | None
    all_time_peak_paise: StrictPaise | None
    all_time_peak_date: date | None


class AccountSpark(APIModel):
    """One Worth row: the balance, when it was last confirmed, and the memory behind
    its sparkline and long-press history sheet."""

    account_id: str
    name: str
    kind: AccountKind
    balance_paise: StrictPaise
    as_of: datetime | None
    points: list[SeriesPoint]  # oldest first
    low_paise: StrictPaise | None
    high_paise: StrictPaise | None
    readings: int


@router.get("/current")
def current(session: SessionDep) -> NetWorthNow:
    net, assets, liabilities = service.current(session)
    return NetWorthNow(
        net_worth_paise=net,
        assets_paise=assets,
        liabilities_paise=liabilities,
        day=today_ist(),
    )


@router.get("/series")
def series(
    session: SessionDep,
    range: Literal["1m", "6m", "fy", "all"] = "6m",
    account_id: str | None = None,
) -> SeriesOut:
    start = service.range_start(range, today_ist())
    points = service.series(session, start=start, account_id=account_id)
    ranged_peak = service.peak(points)
    all_time = (
        ranged_peak
        if start is None
        else service.peak(service.series(session, start=None, account_id=account_id))
    )
    first = points[0][1] if points else None
    last = points[-1][1] if points else None
    return SeriesOut(
        range=range,
        points=[SeriesPoint(date=d, value_paise=v) for d, v in points],
        first_paise=first,
        last_paise=last,
        delta_paise=0 if first is None or last is None else last - first,
        peak_paise=ranged_peak[1] if ranged_peak else None,
        peak_date=ranged_peak[0] if ranged_peak else None,
        all_time_peak_paise=all_time[1] if all_time else None,
        all_time_peak_date=all_time[0] if all_time else None,
    )


@router.get("/accounts")
def account_sparks(
    session: SessionDep, points: int = Query(default=30, ge=2, le=365)
) -> list[AccountSpark]:
    """Every Worth row in one call: balance, as-of cue, and its recent readings."""
    out: list[AccountSpark] = []
    for account in account_service.list_accounts(session):
        balance, as_of = account_service.balance_as_of(session, account.id)
        tail = service.series(session, start=None, account_id=account.id)[-points:]
        values = [v for _, v in tail]
        out.append(
            AccountSpark(
                account_id=account.id,
                name=account.name,
                kind=account.kind,
                balance_paise=balance,
                as_of=as_of,
                points=[SeriesPoint(date=d, value_paise=v) for d, v in tail],
                low_paise=min(values) if values else None,
                high_paise=max(values) if values else None,
                readings=len(values),
            )
        )
    return out
