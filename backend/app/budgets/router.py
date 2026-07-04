from datetime import date
from typing import Optional

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.auth.deps import get_current_user
from app.models.user import User

from app.budgets.schemas import (
    BudgetCreate,
    BudgetUpdate,
    BudgetResponse,
    BudgetUsageResponse,
)
from app.budgets.service import (
    create_budget,
    list_budgets_with_usage,
    update_budget,
    delete_budget,
)

router = APIRouter(prefix="/budgets", tags=["budgets"])


@router.post("", response_model=BudgetResponse, status_code=status.HTTP_201_CREATED)
async def create(
    data: BudgetCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await create_budget(
        db, user.id, data.category_id, data.month, data.limit
    )


@router.get("", response_model=list[BudgetUsageResponse])
async def list_all(
    month: Optional[str] = Query(
        None, description="Month in YYYY-MM format, defaults to the current month"
    ),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    month = month or date.today().strftime("%Y-%m")
    return await list_budgets_with_usage(db, user.id, month)


@router.patch("/{budget_id}", response_model=BudgetResponse)
async def update(
    budget_id: int,
    data: BudgetUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await update_budget(db, user.id, budget_id, limit=data.limit)


@router.delete("/{budget_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete(
    budget_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await delete_budget(db, user.id, budget_id)
