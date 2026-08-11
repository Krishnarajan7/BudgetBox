from fastapi import APIRouter, Query

from budgetbox.api.deps import SessionDep
from budgetbox.api.params import parse_month
from budgetbox.modules.budgets import service
from budgetbox.modules.budgets.schemas import (
    BudgetIn,
    BudgetOut,
    BudgetPatch,
    BudgetSuggestion,
    BudgetTrail,
    BudgetView,
    RebalanceIn,
)

router = APIRouter(prefix="/budgets", tags=["budgets"])


@router.get("")
def list_budgets(session: SessionDep, include_archived: bool = False) -> list[BudgetOut]:
    rows = service.list_budgets(session, include_archived=include_archived)
    return [BudgetOut.model_validate(r) for r in rows]


@router.get("/pace")
def pace(session: SessionDep, month: str | None = None) -> list[BudgetView]:
    return service.pace_views(session, month=parse_month(month))


@router.get("/suggestions")
def suggestions(
    session: SessionDep, months: int = Query(default=3, ge=1, le=24)
) -> list[BudgetSuggestion]:
    return service.suggestions(session, months=months)


@router.post("/rebalance")
def rebalance(session: SessionDep, data: RebalanceIn, month: str | None = None) -> list[BudgetOut]:
    rows = service.rebalance(session, data.budget_ids, month=parse_month(month))
    return [BudgetOut.model_validate(row) for row in rows]


@router.get("/{budget_id}/trail")
def trail(
    session: SessionDep,
    budget_id: str,
    month: str | None = None,
    months: int = Query(default=6, ge=1, le=24),
) -> BudgetTrail:
    """The sparkline, the 'held its line N months running' streak, and this
    period's daily climb against an even pace — the budget row's whole case."""
    return service.trail(session, budget_id, month=parse_month(month), months=months)


@router.put("/{budget_id}")
def upsert_budget(session: SessionDep, budget_id: str, data: BudgetIn) -> BudgetOut:
    return BudgetOut.model_validate(service.upsert(session, budget_id, data))


@router.patch("/{budget_id}")
def patch_budget(session: SessionDep, budget_id: str, data: BudgetPatch) -> BudgetOut:
    return BudgetOut.model_validate(service.patch(session, budget_id, data))


@router.put("/{budget_id}/txns/{txn_id}", status_code=204)
def add_txn(session: SessionDep, budget_id: str, txn_id: str) -> None:
    service.add_txn(session, budget_id, txn_id)


@router.delete("/{budget_id}/txns/{txn_id}", status_code=204)
def remove_txn(session: SessionDep, budget_id: str, txn_id: str) -> None:
    service.remove_txn(session, budget_id, txn_id)
