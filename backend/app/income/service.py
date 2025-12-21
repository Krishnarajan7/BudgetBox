from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from decimal import Decimal

from app.models.transaction import Transaction, TransactionType
from app.models.wallet import Wallet


async def create_income(
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

    income = Transaction(
        user_id=user_id,
        wallet_id=wallet.id,
        category_id=data.category_id,
        type=TransactionType.INCOME,
        amount=Decimal(data.amount),
        occurred_at=data.occurred_at,
        note=data.note,
    )

    wallet.balance += Decimal(data.amount)

    db.add(income)
    await db.commit()
    await db.refresh(income)

    return income


async def update_income(
    db,
    user_id: int,
    income_id: int,
    data,
):
    result = await db.execute(
        select(Transaction)
        .where(
            Transaction.id == income_id,
            Transaction.user_id == user_id,
            Transaction.type == TransactionType.INCOME,
        )
    )
    income = result.scalar_one()

    wallet = await db.get(Wallet, income.wallet_id)

    old_amount = Decimal(income.amount)
    new_amount = Decimal(data.amount) if data.amount is not None else old_amount

    if data.amount is not None:
        wallet.balance -= old_amount
        wallet.balance += new_amount
        income.amount = new_amount

    if data.note is not None:
        income.note = data.note

    if data.occurred_at is not None:
        income.occurred_at = data.occurred_at

    await db.commit()
    await db.refresh(income)

    return income