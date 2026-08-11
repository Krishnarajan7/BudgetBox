from fastapi import APIRouter, Query

from budgetbox.api.deps import SessionDep
from budgetbox.modules.categories import service
from budgetbox.modules.categories.schemas import CategoryIn, CategoryOut, CategoryPatch
from budgetbox.modules.transactions import service as txn_service
from budgetbox.modules.transactions.schemas import CategoryUse

router = APIRouter(prefix="/categories", tags=["categories"])


@router.get("")
def list_categories(session: SessionDep, include_archived: bool = False) -> list[CategoryOut]:
    rows = service.list_categories(session, include_archived=include_archived)
    return [CategoryOut.model_validate(r) for r in rows]


@router.get("/top")
def top_categories(
    session: SessionDep,
    days: int = Query(default=90, ge=1, le=730),
    limit: int = Query(default=5, ge=1, le=20),
) -> list[CategoryUse]:
    """Most-written expense categories over the trailing window — the add sheet's
    chip order, so the five-second entry starts on the right chip."""
    return txn_service.top_category_ids(session, days=days, limit=limit)


@router.put("/{category_id}")
def upsert_category(session: SessionDep, category_id: str, data: CategoryIn) -> CategoryOut:
    return CategoryOut.model_validate(service.upsert(session, category_id, data))


@router.patch("/{category_id}")
def patch_category(session: SessionDep, category_id: str, data: CategoryPatch) -> CategoryOut:
    return CategoryOut.model_validate(service.patch(session, category_id, data))
