from fastapi import APIRouter

from budgetbox.api.deps import SessionDep
from budgetbox.api.params import parse_month
from budgetbox.modules.budgets import service
from budgetbox.modules.budgets.schemas import BudgetIn, BudgetOut, BudgetPatch, BudgetView

router = APIRouter(prefix="/budgets", tags=["budgets"])


@router.get("")
def list_budgets(session: SessionDep, include_archived: bool = False) -> list[BudgetOut]:
    rows = service.list_budgets(session, include_archived=include_archived)
    return [BudgetOut.model_validate(r) for r in rows]


@router.get("/pace")
def pace(session: SessionDep, month: str | None = None) -> list[BudgetView]:
    return service.pace_views(session, month=parse_month(month))


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
