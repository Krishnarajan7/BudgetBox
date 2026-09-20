"""The work book's rows. Thin: the phone owns the arithmetic (what is owed,
what to pass on); the server stores, lists and drops."""

from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from budgetbox.core.errors import NotFound
from budgetbox.core.ids import require_uuid
from budgetbox.db.base import Base
from budgetbox.modules.work.models import Client, Project, ProjectLink, QuoteRevision
from budgetbox.modules.work.schemas import ClientIn, LinkIn, ProjectIn, QuoteIn


def _get[T: Base](session: Session, model: type[T], row_id: str) -> T:
    row = session.get(model, row_id)
    if row is None:
        raise NotFound(f"no {model.__tablename__} {row_id}")
    return row


def _require_ref(session: Session, model: type[Base], row_id: str, what: str) -> None:
    if session.get(model, row_id) is None:
        raise NotFound(f"no {what} {row_id}")


# ————— clients —————


def list_clients(session: Session, *, include_archived: bool = False) -> list[Client]:
    stmt = select(Client).order_by(Client.name, Client.id)
    if not include_archived:
        stmt = stmt.where(Client.archived.is_(False))
    return list(session.scalars(stmt))


def upsert_client(session: Session, client_id: str, data: ClientIn) -> Client:
    client_id = require_uuid(client_id)
    row = session.get(Client, client_id)
    if row is None:
        row = Client(id=client_id)
        session.add(row)
    row.name = data.name
    row.note = data.note
    row.archived = data.archived
    session.commit()
    return row


def delete_client(session: Session, client_id: str) -> None:
    session.delete(_get(session, Client, client_id))
    session.commit()


# ————— projects —————


def list_projects(session: Session) -> list[Project]:
    return list(session.scalars(select(Project).order_by(Project.started_at, Project.id)))


def upsert_project(session: Session, project_id: str, data: ProjectIn) -> Project:
    project_id = require_uuid(project_id)
    _require_ref(session, Client, data.client_id, "client")
    row = session.get(Project, project_id)
    if row is None:
        row = Project(id=project_id)
        session.add(row)
    row.client_id = data.client_id
    row.name = data.name
    row.kind = data.kind
    row.quote_paise = data.quote_paise
    row.billing_day = data.billing_day
    row.status = data.status
    row.started_at = data.started_at
    row.note = data.note
    session.commit()
    return row


def delete_project(session: Session, project_id: str) -> None:
    """A project takes its quote history and its claims with it. The
    children go first, as their own statements, because SQLite checks the
    foreign keys per statement and the ledger lines themselves stay."""
    row = _get(session, Project, project_id)
    session.execute(delete(ProjectLink).where(ProjectLink.project_id == project_id))
    session.execute(delete(QuoteRevision).where(QuoteRevision.project_id == project_id))
    session.delete(row)
    session.commit()


# ————— quotes —————


def list_quotes(session: Session) -> list[QuoteRevision]:
    return list(session.scalars(select(QuoteRevision).order_by(QuoteRevision.at, QuoteRevision.id)))


def upsert_quote(session: Session, quote_id: str, data: QuoteIn) -> QuoteRevision:
    quote_id = require_uuid(quote_id)
    _require_ref(session, Project, data.project_id, "project")
    row = session.get(QuoteRevision, quote_id)
    if row is None:
        row = QuoteRevision(id=quote_id)
        session.add(row)
    row.project_id = data.project_id
    row.paise = data.paise
    row.reason = data.reason
    row.at = data.at
    session.commit()
    return row


def delete_quote(session: Session, quote_id: str) -> None:
    session.delete(_get(session, QuoteRevision, quote_id))
    session.commit()


# ————— links —————


def list_links(session: Session) -> list[ProjectLink]:
    return list(session.scalars(select(ProjectLink).order_by(ProjectLink.at, ProjectLink.id)))


def upsert_link(session: Session, link_id: str, data: LinkIn) -> ProjectLink:
    from budgetbox.modules.transactions.models import Txn

    link_id = require_uuid(link_id)
    _require_ref(session, Project, data.project_id, "project")
    _require_ref(session, Txn, data.txn_id, "txn")
    row = session.get(ProjectLink, link_id)
    if row is None:
        row = ProjectLink(id=link_id)
        session.add(row)
    row.project_id = data.project_id
    row.txn_id = data.txn_id
    row.role = data.role
    row.billable = data.billable
    row.note = data.note
    row.at = data.at
    session.commit()
    return row


def delete_link(session: Session, link_id: str) -> None:
    session.delete(_get(session, ProjectLink, link_id))
    session.commit()
