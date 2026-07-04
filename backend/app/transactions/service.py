from datetime import date as _date, timedelta
from typing import Optional

from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.transaction import Transaction, TransactionType


async def list_transactions(
    db: AsyncSession,
    user_id: int,
    *,
    type: Optional[TransactionType] = None,
    wallet_id: Optional[int] = None,
    category_id: Optional[int] = None,
    start_date: Optional[_date] = None,
    end_date: Optional[_date] = None,
    limit: int = 50,
    offset: int = 0,
):
    where = [Transaction.user_id == user_id]
    if type is not None:
        where.append(Transaction.type == type)
    if wallet_id is not None:
        where.append(Transaction.wallet_id == wallet_id)
    if category_id is not None:
        where.append(Transaction.category_id == category_id)
    if start_date is not None:
        where.append(Transaction.occurred_at >= start_date)
    if end_date is not None:
        where.append(Transaction.occurred_at < end_date + timedelta(days=1))

    total = await db.scalar(
        select(func.count(Transaction.id)).where(*where)
    ) or 0

    result = await db.execute(
        select(Transaction)
        .where(*where)
        .order_by(Transaction.occurred_at.desc(), Transaction.id.desc())
        .limit(limit)
        .offset(offset)
    )
    items = result.scalars().all()

    return {
        "total": total,
        "limit": limit,
        "offset": offset,
        "items": items,
    }
