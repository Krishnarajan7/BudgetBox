"""Cheap cache-refresh affordance (not a sync protocol): which rows changed since
an instant, per resource, keyed off the updated_at every table carries."""

from datetime import datetime
from typing import Any

from fastapi import APIRouter
from sqlalchemy import select
from sqlalchemy.orm import InstrumentedAttribute

from budgetbox.api.deps import SessionDep
from budgetbox.api.schemas import APIModel, Instant
from budgetbox.core.time import now_utc
from budgetbox.modules.accounts.models import Account, BalanceAnchor
from budgetbox.modules.budgets.models import Budget
from budgetbox.modules.categories.models import Category
from budgetbox.modules.goals.models import Goal
from budgetbox.modules.recurring.models import Recurring
from budgetbox.modules.settings.models import Setting
from budgetbox.modules.transactions.models import Activity, DaySeal, Pinned, Txn

router = APIRouter(prefix="/changes", tags=["changes"])

_TRACKED: dict[str, tuple[type[Any], InstrumentedAttribute[Any]]] = {
    "accounts": (Account, Account.id),
    "balance_anchors": (BalanceAnchor, BalanceAnchor.id),
    "categories": (Category, Category.id),
    "txns": (Txn, Txn.id),
    "pinned": (Pinned, Pinned.id),
    "day_seals": (DaySeal, DaySeal.date),
    "activities": (Activity, Activity.id),
    "settings": (Setting, Setting.key),
    "recurrings": (Recurring, Recurring.id),
    "budgets": (Budget, Budget.id),
    "goals": (Goal, Goal.id),
}


def register(resource: str, model: type[Any], pk: InstrumentedAttribute[Any]) -> None:
    """Later modules (notes, journal, …) opt in without editing this file."""
    _TRACKED[resource] = (model, pk)


class ChangesOut(APIModel):
    now: datetime
    changed: dict[str, list[str]]


@router.get("")
def changes(session: SessionDep, since: Instant) -> ChangesOut:
    now = now_utc()
    changed: dict[str, list[str]] = {}
    for resource, (model, pk) in _TRACKED.items():
        rows: list[Any] = list(session.scalars(select(pk).where(model.updated_at > since)))
        if rows:
            changed[resource] = [str(r) for r in rows]
    return ChangesOut(now=now, changed=changed)
