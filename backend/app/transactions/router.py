from datetime import date
from typing import Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.deps import PaginationParams, pagination
from app.auth.deps import get_current_user
from app.models.user import User
from app.models.transaction import TransactionType

from app.transactions.service import list_transactions
from app.transactions.schemas import TransactionListResponse, TransactionResponse


router = APIRouter(prefix="/transactions", tags=["transactions"])


def _serialize(tx) -> TransactionResponse:
    return TransactionResponse(
        id=tx.id,
        type=tx.type,
        amount=float(tx.amount),
        wallet_id=tx.wallet_id,
        category_id=tx.category_id,
        note=tx.note,
        occurred_at=tx.occurred_at,
    )


@router.get("", response_model=TransactionListResponse)
async def list_all(
    type: Optional[TransactionType] = Query(None, description="Filter by INCOME or EXPENSE"),
    wallet_id: Optional[int] = Query(None),
    category_id: Optional[int] = Query(None),
    start_date: Optional[date] = Query(None),
    end_date: Optional[date] = Query(None),
    page: PaginationParams = Depends(pagination),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    data = await list_transactions(
        db,
        user.id,
        type=type,
        wallet_id=wallet_id,
        category_id=category_id,
        start_date=start_date,
        end_date=end_date,
        limit=page.limit,
        offset=page.offset,
    )
    return TransactionListResponse(
        total=data["total"],
        limit=data["limit"],
        offset=data["offset"],
        items=[_serialize(t) for t in data["items"]],
    )
