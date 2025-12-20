from decimal import Decimal

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.transaction import Transaction, TransactionType
from app.models.wallet import Wallet


async def create_expense(
    db: AsyncSession,
    user_id: int,
    data,
) -> Transaction:
    result = await db.execute(
        select(Wallet).where(
            Wallet.id == data.wallet_id,
            Wallet.user_id == user_id,
        )
    )
    wallet = result.scalar_one_or_none()

    if not wallet:
        raise ValueError("Wallet not found")

    expense = Transaction(
        user_id=user_id,
        wallet_id=wallet.id,
        category_id=data.category_id,
        type=TransactionType.EXPENSE,
        amount=Decimal(data.amount),
        occurred_at=data.occurred_at,
        note=data.note,
    )

    wallet.balance -= Decimal(data.amount)

    db.add(expense)
    await db.commit()
    await db.refresh(expense)

    return expense
