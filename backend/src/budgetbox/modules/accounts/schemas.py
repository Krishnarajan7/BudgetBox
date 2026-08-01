from datetime import datetime

from pydantic import Field

from budgetbox.api.schemas import APIModel, Instant, StrictPaise
from budgetbox.modules.accounts.models import AccountKind


class AccountIn(APIModel):
    name: str = Field(min_length=1, max_length=60)
    kind: AccountKind
    sort_order: int = 0


class AccountPatch(APIModel):
    name: str | None = Field(default=None, min_length=1, max_length=60)
    kind: AccountKind | None = None
    sort_order: int | None = None
    archived: bool | None = None


class AnchorIn(APIModel):
    """A user-confirmed balance. `at` defaults to now; anchors can be backdated
    (balance derivation handles any anchor time exactly)."""

    balance_paise: StrictPaise
    at: Instant | None = None


class AccountOut(APIModel):
    id: str
    name: str
    kind: AccountKind
    sort_order: int
    archived: bool
    balance_paise: StrictPaise
    as_of: datetime | None
    created_at: datetime
    updated_at: datetime
