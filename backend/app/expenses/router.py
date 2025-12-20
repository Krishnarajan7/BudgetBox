from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from datetime import date

from app.core.database import get_db
from app.auth.deps import get_current_user
from app.models.user import User
from app.models.transaction import Transaction, TransactionType

router = APIRouter(prefix="/expenses", tags=["expenses"])


@router.get("")
async def list_expenses(
    start_date: date | None = Query(None),
    end_date: date | None = Query(None),
    wallet_id: int | None = Query(None),
    category_id: int | None = Query(None),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    query = select(Transaction).where(
        Transaction.user_id == user.id,
        Transaction.type == TransactionType.EXPENSE,
    )

    if start_date and end_date:
        query = query.where(Transaction.occurred_at.between(start_date, end_date))

    if wallet_id:
        query = query.where(Transaction.wallet_id == wallet_id)

    if category_id:
        query = query.where(Transaction.category_id == category_id)

    result = await db.execute(query.order_by(Transaction.occurred_at.desc()))
    expenses = result.scalars().all()

    return [
        {
            "id": e.id,
            "amount": float(e.amount),
            "occurred_at": e.occurred_at,
            "wallet_id": e.wallet_id,
            "category_id": e.category_id,
            "note": e.note,
        }
        for e in expenses
    ]
