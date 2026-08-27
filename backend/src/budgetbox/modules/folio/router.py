from typing import Annotated

from fastapi import APIRouter, Query

from budgetbox.api.deps import SessionDep
from budgetbox.core.errors import Invalid
from budgetbox.modules.folio import amfi, service
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

router = APIRouter(prefix="/folio", tags=["folio"])


@router.get("/overview")
def overview(session: SessionDep) -> OverviewOut:
    return service.overview(session)


@router.get("/funds")
def list_funds(session: SessionDep, include_archived: bool = False) -> list[FundOut]:
    return service.funds(session, include_archived=include_archived)


@router.get("/funds/{fund_id}")
def get_fund(session: SessionDep, fund_id: str) -> FundOut:
    return service.fund_view(session, service.get_fund(session, fund_id))


@router.put("/funds/{fund_id}")
def upsert_fund(session: SessionDep, fund_id: str, data: FundIn) -> FundOut:
    return service.fund_view(session, service.upsert_fund(session, fund_id, data))


@router.patch("/funds/{fund_id}")
def patch_fund(session: SessionDep, fund_id: str, data: FundPatch) -> FundOut:
    return service.fund_view(session, service.patch_fund(session, fund_id, data))


@router.delete("/funds/{fund_id}", status_code=204)
def delete_fund(session: SessionDep, fund_id: str) -> None:
    service.delete_fund(session, fund_id)


@router.get("/funds/{fund_id}/entries")
def list_entries(session: SessionDep, fund_id: str) -> list[EntryOut]:
    service.get_fund(session, fund_id)
    return service.entries(session, fund_id)


@router.post("/funds/{fund_id}/contribute")
def contribute(session: SessionDep, fund_id: str, data: ContributeIn) -> EntryOut:
    return service.contribute(session, fund_id, data)


@router.post("/funds/{fund_id}/redeem")
def redeem(session: SessionDep, fund_id: str, data: RedeemIn) -> EntryOut:
    return service.redeem(session, fund_id, data)


@router.post("/funds/{fund_id}/value")
def set_value(session: SessionDep, fund_id: str, data: ValueIn) -> FundOut:
    return service.set_value(session, fund_id, data)


@router.get("/series")
def series(
    session: SessionDep, days: Annotated[int, Query(ge=7, le=1825)] = 180
) -> list[FolioPoint]:
    return service.series(session, days)


@router.get("/schemes")
def schemes(query: str, limit: Annotated[int, Query(ge=1, le=25)] = 12) -> list[SchemeOut]:
    """Search AMFI's daily file. Live, because it is used a handful of times
    in a lifetime and a cache would be machinery guarding nothing."""
    if len(query.strip()) < 3:
        raise Invalid("Type at least three letters.")
    try:
        return service.search_schemes(query, limit)
    except amfi.AmfiError as exc:
        raise Invalid(exc.detail) from exc


@router.post("/refresh")
def refresh(session: SessionDep) -> OverviewOut:
    """Pull today's NAVs now rather than waiting for the nightly job."""
    try:
        service.refresh_navs(session)
        service.anchor_worth(session)
    except amfi.AmfiError as exc:
        raise Invalid(exc.detail) from exc
    return service.overview(session)
