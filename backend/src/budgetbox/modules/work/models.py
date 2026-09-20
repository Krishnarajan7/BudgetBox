import datetime as dt
import enum

from sqlalchemy import Boolean, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from budgetbox.db.base import Base, StampedMixin, UTCInstant, pk_id, str_enum


class ProjectKind(enum.StrEnum):
    one_time = "one_time"
    monthly = "monthly"


class ProjectStatus(enum.StrEnum):
    quoted = "quoted"
    active = "active"
    done = "done"
    dropped = "dropped"


class LinkRole(enum.StrEnum):
    received = "received"
    cost = "cost"


class Client(Base, StampedMixin):
    """Someone the work is done for."""

    __tablename__ = "clients"

    id: Mapped[str] = pk_id()
    name: Mapped[str] = mapped_column(String(60))
    note: Mapped[str | None] = mapped_column(Text, default=None)
    archived: Mapped[bool] = mapped_column(Boolean, default=False)


class Project(Base, StampedMixin):
    """One piece of work for one client. `quote_paise` is the quote as it
    stands; the history of how it got there lives in quote_revisions."""

    __tablename__ = "projects"

    id: Mapped[str] = pk_id()
    client_id: Mapped[str] = mapped_column(ForeignKey("clients.id"), index=True)
    name: Mapped[str] = mapped_column(String(80))
    kind: Mapped[ProjectKind] = mapped_column(str_enum(ProjectKind, "project_kind"))
    quote_paise: Mapped[int] = mapped_column(Integer)
    billing_day: Mapped[int | None] = mapped_column(Integer, default=None)
    status: Mapped[ProjectStatus] = mapped_column(str_enum(ProjectStatus, "project_status"))
    started_at: Mapped[dt.datetime] = mapped_column(UTCInstant())
    note: Mapped[str | None] = mapped_column(Text, default=None)


class QuoteRevision(Base, StampedMixin):
    __tablename__ = "quote_revisions"

    id: Mapped[str] = pk_id()
    project_id: Mapped[str] = mapped_column(ForeignKey("projects.id"), index=True)
    paise: Mapped[int] = mapped_column(Integer)
    reason: Mapped[str | None] = mapped_column(Text, default=None)
    at: Mapped[dt.datetime] = mapped_column(UTCInstant())


class ProjectLink(Base, StampedMixin):
    """A ledger line claimed by a project: money received, or a cost it
    caused. `billable` on a cost means it sat outside the quote."""

    __tablename__ = "project_links"

    id: Mapped[str] = pk_id()
    project_id: Mapped[str] = mapped_column(ForeignKey("projects.id"), index=True)
    txn_id: Mapped[str] = mapped_column(ForeignKey("txns.id"), index=True)
    role: Mapped[LinkRole] = mapped_column(str_enum(LinkRole, "link_role"))
    billable: Mapped[bool] = mapped_column(Boolean, default=False)
    note: Mapped[str | None] = mapped_column(Text, default=None)
    at: Mapped[dt.datetime] = mapped_column(UTCInstant())
