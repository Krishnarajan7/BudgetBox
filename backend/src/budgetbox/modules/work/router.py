"""/v1/clients, /v1/projects, /v1/quotes, /v1/project-links — the work book."""

from fastapi import APIRouter

from budgetbox.api.deps import SessionDep
from budgetbox.modules.work import service
from budgetbox.modules.work.schemas import (
    ClientIn,
    ClientOut,
    LinkIn,
    LinkOut,
    ProjectIn,
    ProjectOut,
    QuoteIn,
    QuoteOut,
)

router = APIRouter(tags=["work"])


@router.get("/clients")
def list_clients(session: SessionDep, include_archived: bool = False) -> list[ClientOut]:
    return [
        ClientOut.model_validate(r)
        for r in service.list_clients(session, include_archived=include_archived)
    ]


@router.put("/clients/{client_id}")
def upsert_client(session: SessionDep, client_id: str, data: ClientIn) -> ClientOut:
    return ClientOut.model_validate(service.upsert_client(session, client_id, data))


@router.delete("/clients/{client_id}", status_code=204)
def delete_client(session: SessionDep, client_id: str) -> None:
    service.delete_client(session, client_id)


@router.get("/projects")
def list_projects(session: SessionDep) -> list[ProjectOut]:
    return [ProjectOut.model_validate(r) for r in service.list_projects(session)]


@router.put("/projects/{project_id}")
def upsert_project(session: SessionDep, project_id: str, data: ProjectIn) -> ProjectOut:
    return ProjectOut.model_validate(service.upsert_project(session, project_id, data))


@router.delete("/projects/{project_id}", status_code=204)
def delete_project(session: SessionDep, project_id: str) -> None:
    service.delete_project(session, project_id)


@router.get("/quotes")
def list_quotes(session: SessionDep) -> list[QuoteOut]:
    return [QuoteOut.model_validate(r) for r in service.list_quotes(session)]


@router.put("/quotes/{quote_id}")
def upsert_quote(session: SessionDep, quote_id: str, data: QuoteIn) -> QuoteOut:
    return QuoteOut.model_validate(service.upsert_quote(session, quote_id, data))


@router.delete("/quotes/{quote_id}", status_code=204)
def delete_quote(session: SessionDep, quote_id: str) -> None:
    service.delete_quote(session, quote_id)


@router.get("/project-links")
def list_links(session: SessionDep) -> list[LinkOut]:
    return [LinkOut.model_validate(r) for r in service.list_links(session)]


@router.put("/project-links/{link_id}")
def upsert_link(session: SessionDep, link_id: str, data: LinkIn) -> LinkOut:
    return LinkOut.model_validate(service.upsert_link(session, link_id, data))


@router.delete("/project-links/{link_id}", status_code=204)
def delete_link(session: SessionDep, link_id: str) -> None:
    service.delete_link(session, link_id)
