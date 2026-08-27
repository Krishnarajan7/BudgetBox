from typing import Annotated

from fastapi import APIRouter, Query

from budgetbox.api.deps import SessionDep
from budgetbox.modules.slate import service
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

router = APIRouter(prefix="/slate", tags=["slate"])


@router.get("/overview")
def overview(session: SessionDep) -> OverviewOut:
    return service.overview(session)


@router.get("/people")
def list_people(session: SessionDep, include_archived: bool = False) -> list[PersonOut]:
    return service.people(session, include_archived=include_archived)


@router.get("/people/{person_id}")
def get_person(session: SessionDep, person_id: str) -> PersonOut:
    return service.person_view(session, person_id)


@router.put("/people/{person_id}")
def upsert_person(session: SessionDep, person_id: str, data: PersonIn) -> PersonOut:
    service.upsert_person(session, person_id, data)
    return service.person_view(session, person_id)


@router.patch("/people/{person_id}")
def patch_person(session: SessionDep, person_id: str, data: PersonPatch) -> PersonOut:
    service.patch_person(session, person_id, data)
    return service.person_view(session, person_id)


@router.delete("/people/{person_id}", status_code=204)
def delete_person(session: SessionDep, person_id: str) -> None:
    service.delete_person(session, person_id)


@router.get("/people/{person_id}/entries")
def list_entries(session: SessionDep, person_id: str) -> list[EntryOut]:
    service.get_person(session, person_id)
    return service.entries(session, person_id)


@router.post("/people/{person_id}/lend")
def lend(session: SessionDep, person_id: str, data: LendIn) -> EntryOut:
    return service.lend(session, person_id, data)


@router.post("/people/{person_id}/borrow")
def borrow(session: SessionDep, person_id: str, data: LendIn) -> EntryOut:
    return service.borrow(session, person_id, data)


@router.post("/people/{person_id}/repay")
def repay(session: SessionDep, person_id: str, data: RepayIn) -> EntryOut:
    return service.repay(session, person_id, data)


@router.post("/people/{person_id}/close")
def close(session: SessionDep, person_id: str, data: CloseIn) -> EntryOut:
    return service.close(session, person_id, data)


@router.post("/people/{person_id}/adopt")
def adopt(session: SessionDep, person_id: str, data: AdoptIn) -> EntryOut:
    return service.adopt(session, person_id, data)


@router.get("/adoptable")
def adoptable(
    session: SessionDep, limit: Annotated[int, Query(ge=1, le=100)] = 40
) -> list[AdoptableOut]:
    return service.adoptable(session, limit)
