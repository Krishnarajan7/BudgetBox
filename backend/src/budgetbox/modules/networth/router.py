from datetime import date
from typing import Literal

from fastapi import APIRouter

from budgetbox.api.deps import SessionDep
from budgetbox.api.schemas import APIModel, StrictPaise
from budgetbox.core.time import today_ist
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
    return SeriesOut(
        range=range,
        points=[SeriesPoint(date=d, value_paise=v) for d, v in points],
    )
