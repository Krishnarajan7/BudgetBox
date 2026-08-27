from datetime import datetime
from typing import Annotated

from pydantic import Field

from budgetbox.api.schemas import APIModel, Instant, PositivePaise
from budgetbox.modules.slate.models import SlateKind

Name = Annotated[str, Field(min_length=1, max_length=60)]
Relation = Annotated[str | None, Field(max_length=40)]


class PersonIn(APIModel):
    name: Name
    relation: Relation = None
    note: str | None = None


class PersonPatch(APIModel):
    name: Name | None = None
    relation: Relation = None
    note: str | None = None
    archived: bool | None = None


class EntryOut(APIModel):
    id: str
    person_id: str
    kind: SlateKind
    amount_paise: int
    at: datetime
    note: str | None
    txn_id: str | None
    created_at: datetime
    updated_at: datetime


class PersonOut(APIModel):
    id: str
    name: str
    relation: str | None
    note: str | None
    archived: bool
    # Positive: they owe you. Negative: you owe them. Zero: the slate is clean.
    balance_paise: int
    # Everything that ever went out to them, and everything that came back —
    # so a settled slate still shows the history it settled.
    lent_paise: int
    returned_paise: int
    entries: int
    # Loops that closed by being repaid in full, and how many loops there
    # have been. '5 of 5 returned' — a fact, not a score.
    loops_closed: int
    loops_total: int
    since: datetime | None
    last_at: datetime | None
    # When the current balance first went out; null on a clean slate. The age
    # the screen prints, so nothing has to nag.
    outstanding_since: datetime | None


class OverviewOut(APIModel):
    # What the world owes you, what you owe it, and the difference.
    owed_to_you_paise: int
    you_owe_paise: int
    net_paise: int
    people_in_debt: int
    people_you_owe: int
    # The 'On the slate' account balance. Equal to net_paise unless something
    # has gone wrong — the app says so rather than quietly disagreeing.
    slate_account_paise: int
    balanced: bool


class LendIn(APIModel):
    """Money out. `account_id` is the pocket it leaves — GPay, cash, bank."""

    amount_paise: PositivePaise
    account_id: str
    at: Instant | None = None
    note: str | None = None


class RepayIn(APIModel):
    """Money back. `account_id` is where it lands — usually where it left."""

    amount_paise: PositivePaise
    account_id: str
    at: Instant | None = None
    note: str | None = None


class CloseIn(APIModel):
    """Let it go (a lend that will not return) or accept a write-off (a borrow
    the other side forgave). Amount defaults to the whole standing balance."""

    amount_paise: PositivePaise | None = None
    at: Instant | None = None
    note: str | None = None


class AdoptIn(APIModel):
    """An expense already in the book that was really a loan. The txn is
    converted into a transfer onto the slate rather than a second line being
    written beside it — no double count, and the old month gets more honest."""

    txn_id: str


class AdoptableOut(APIModel):
    """An expense that looks like it might have been a loan."""

    txn_id: str
    title: str
    amount_paise: int
    at: datetime
    account_id: str
    category: str | None
