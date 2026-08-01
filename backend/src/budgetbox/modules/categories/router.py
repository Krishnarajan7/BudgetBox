from fastapi import APIRouter

from budgetbox.api.deps import SessionDep
from budgetbox.modules.categories import service
from budgetbox.modules.categories.schemas import CategoryIn, CategoryOut, CategoryPatch

router = APIRouter(prefix="/categories", tags=["categories"])


@router.get("")
def list_categories(session: SessionDep, include_archived: bool = False) -> list[CategoryOut]:
    rows = service.list_categories(session, include_archived=include_archived)
    return [CategoryOut.model_validate(r) for r in rows]


@router.put("/{category_id}")
def upsert_category(session: SessionDep, category_id: str, data: CategoryIn) -> CategoryOut:
    return CategoryOut.model_validate(service.upsert(session, category_id, data))


@router.patch("/{category_id}")
def patch_category(session: SessionDep, category_id: str, data: CategoryPatch) -> CategoryOut:
    return CategoryOut.model_validate(service.patch(session, category_id, data))
