from datetime import date, datetime

from pydantic import Field

from budgetbox.api.schemas import APIModel, Instant, PositivePaise
from budgetbox.modules.transactions.models import ActivityAction, TxnType


class TxnIn(APIModel):
    amount_paise: PositivePaise
    type: TxnType
    account_id: str
    to_account_id: str | None = None
    category_id: str | None = None
    title: str = Field(min_length=1, max_length=120)
    note: str | None = None
    at: Instant
    goal_id: str | None = None


class TxnPatch(APIModel):
    amount_paise: PositivePaise | None = None
    type: TxnType | None = None
    account_id: str | None = None
    to_account_id: str | None = None
    category_id: str | None = None
    title: str | None = Field(default=None, min_length=1, max_length=120)
    note: str | None = None
    at: Instant | None = None
    goal_id: str | None = None


class TxnOut(APIModel):
    id: str
    amount_paise: PositivePaise
    type: TxnType
    account_id: str
    to_account_id: str | None
    category_id: str | None
    title: str
    note: str | None
    at: datetime
    goal_id: str | None
    recurring_id: str | None
    created_at: datetime
    updated_at: datetime


class TxnPage(APIModel):
    items: list[TxnOut]
    next_cursor: str | None


class TitleSuggestion(APIModel):
    """Autocomplete carrying category/account memory (port of TxnRepo.suggestTitles)."""

    title: str
    category_id: str | None
    account_id: str | None


class PinnedIn(APIModel):
    title: str = Field(min_length=1, max_length=120)
    amount_paise: PositivePaise
    category_id: str
    account_id: str
    sort_order: int = 0


class PinnedOut(APIModel):
    id: str
    title: str
    amount_paise: PositivePaise
    category_id: str
    account_id: str
    sort_order: int
    created_at: datetime
    updated_at: datetime


class StampIn(APIModel):
    at: Instant | None = None


class SealOut(APIModel):
    date: date
    sealed_at: datetime


class ActivityOut(APIModel):
    id: str
    txn_id: str
    action: ActivityAction
    at: datetime


class UndoResult(APIModel):
    action: ActivityAction
    txn: TxnOut | None
