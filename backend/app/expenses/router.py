from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession
from datetime import date
from typing import Optional

from app.core.database import get_db
from app.auth.deps import get_current_user
from app.models.user import User

from app.expenses.schemas import ExpenseCreate, ExpenseUpdate
from app.expenses.service import (
    create_expense,
    update_expense,
    delete_expense,
    list_expenses,
)

router = APIRouter(prefix="/expenses", tags=["expenses"])


@router.post("", status_code=status.HTTP_201_CREATED)
async def create(
    data: ExpenseCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    expense = await create_expense(db, user.id, data)
    return {
        "id": expense.id,
        "amount": float(expense.amount),
        "wallet_id": expense.wallet_id,
        "category_id": expense.category_id,
        "note": expense.note,
        "occurred_at": expense.occurred_at,
    }


@router.get("")
async def list_expenses_endpoint(
    start_date: Optional[date] = Query(None),
    end_date: Optional[date] = Query(None),
    wallet_id: Optional[int] = Query(None),
    category_id: Optional[int] = Query(None),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    expenses = await list_expenses(db, user.id)

    return [
        {
            "id": e.id,
            "amount": float(e.amount),
            "wallet_id": e.wallet_id,
            "category_id": e.category_id,
            "note": e.note,
            "occurred_at": e.occurred_at,
        }
        for e in expenses
    ]


@router.patch("/{expense_id}")
async def patch_expense(
    expense_id: int,
    data: ExpenseUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    expense = await update_expense(db, user.id, expense_id, data)
    return {
        "id": expense.id,
        "amount": float(expense.amount),
        "wallet_id": expense.wallet_id,
        "category_id": expense.category_id,
        "note": expense.note,
        "occurred_at": expense.occurred_at,
    }


@router.delete("/{expense_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete(
    expense_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await delete_expense(db, user.id, expense_id)
