from datetime import datetime
from typing import Annotated

from pydantic import Field

from budgetbox.api.schemas import APIModel, Instant
from budgetbox.modules.work.models import LinkRole, ProjectKind, ProjectStatus

Name60 = Annotated[str, Field(strict=True, min_length=1, max_length=60)]
Name80 = Annotated[str, Field(strict=True, min_length=1, max_length=80)]
Note = Annotated[str | None, Field(max_length=1000)]
Paise = Annotated[int, Field(strict=True, ge=0, le=10_000_000_000)]


class ClientIn(APIModel):
    name: Name60
    note: Note = None
    archived: bool = False


class ClientOut(APIModel):
    id: str
    name: str
    note: str | None
    archived: bool
    created_at: datetime
    updated_at: datetime


class ProjectIn(APIModel):
    client_id: str
    name: Name80
    kind: ProjectKind
    quote_paise: Paise
    billing_day: Annotated[int | None, Field(ge=1, le=31)] = None
    status: ProjectStatus = ProjectStatus.active
    started_at: Instant
    note: Note = None


class ProjectOut(APIModel):
    id: str
    client_id: str
    name: str
    kind: ProjectKind
    quote_paise: int
    billing_day: int | None
    status: ProjectStatus
    started_at: datetime
    note: str | None
    created_at: datetime
    updated_at: datetime


class QuoteIn(APIModel):
    project_id: str
    paise: Paise
    reason: Note = None
    at: Instant


class QuoteOut(APIModel):
    id: str
    project_id: str
    paise: int
    reason: str | None
    at: datetime
    created_at: datetime
    updated_at: datetime


class LinkIn(APIModel):
    project_id: str
    txn_id: str
    role: LinkRole
    billable: bool = False
    note: Note = None
    at: Instant


class LinkOut(APIModel):
    id: str
    project_id: str
    txn_id: str
    role: LinkRole
    billable: bool
    note: str | None
    at: datetime
    created_at: datetime
    updated_at: datetime
