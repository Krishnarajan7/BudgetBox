from datetime import date
from typing import Optional

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.auth.deps import get_current_user
from app.models.user import User

from app.income.schemas import IncomeCreate, IncomeUpdate, IncomeResponse
from app.income.service import (
    create_income,
    list_incomes,
    get_income,
    update_income,
    delete_income,
)


router = APIRouter(prefix="/income", tags=["income"])


def _serialize(income) -> dict:
    return {
        "id": income.id,
        "amount": float(income.amount),
        "wallet_id": income.wallet_id,
        "category_id": income.category_id,
        "note": income.note,
        "occurred_at": income.occurred_at,
    }


@router.post("", status_code=status.HTTP_201_CREATED, response_model=IncomeResponse)
async def create(
    data: IncomeCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    income = await create_income(db, user.id, data)
    return _serialize(income)


@router.get("", response_model=list[IncomeResponse])
async def list_all(
    start_date: Optional[date] = Query(None),
    end_date: Optional[date] = Query(None),
    wallet_id: Optional[int] = Query(None),
    category_id: Optional[int] = Query(None),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    items = await list_incomes(
        db,
        user.id,
        start_date=start_date,
        end_date=end_date,
        wallet_id=wallet_id,
        category_id=category_id,
    )
    return [_serialize(i) for i in items]


@router.get("/{income_id}", response_model=IncomeResponse)
async def get_one(
    income_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    income = await get_income(db, user.id, income_id)
    return _serialize(income)


@router.patch("/{income_id}", response_model=IncomeResponse)
async def patch(
    income_id: int,
    data: IncomeUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    income = await update_income(db, user.id, income_id, data)
    return _serialize(income)


@router.delete("/{income_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete(
    income_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await delete_income(db, user.id, income_id)
