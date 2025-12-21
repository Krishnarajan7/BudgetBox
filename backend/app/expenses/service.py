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

    amount = Decimal(data.amount)

    expense = Transaction(
        user_id=user_id,
        wallet_id=wallet.id,
        category_id=data.category_id,
        type=TransactionType.EXPENSE,
        amount=amount,
        occurred_at=data.occurred_at,
        note=data.note,
    )

    wallet.balance -= amount

    db.add(expense)
    await db.commit()
    await db.refresh(expense)
    return expense


async def update_expense(
    db: AsyncSession,
    user_id: int,
    expense_id: int,
    data,
) -> Transaction:
    result = await db.execute(
        select(Transaction).where(
            Transaction.id == expense_id,
            Transaction.user_id == user_id,
            Transaction.type == TransactionType.EXPENSE,
        )
    )
    expense = result.scalar_one()

    result = await db.execute(
        select(Wallet).where(
            Wallet.id == expense.wallet_id,
            Wallet.user_id == user_id,
        )
    )
    wallet = result.scalar_one()

    old_amount = Decimal(expense.amount)
    new_amount = Decimal(data.amount) if data.amount is not None else old_amount

    if data.amount is not None:
        wallet.balance += old_amount
        wallet.balance -= new_amount
        expense.amount = new_amount

    if data.category_id is not None:
        expense.category_id = data.category_id

    if data.note is not None:
        expense.note = data.note

    if data.occurred_at is not None:
        expense.occurred_at = data.occurred_at

    await db.commit()
    await db.refresh(expense)
    return expense


async def list_expenses(
    db: AsyncSession,
    user_id: int,
    start_date=None,
    end_date=None,
    wallet_id=None,
    category_id=None,
):
    query = select(Transaction).where(
        Transaction.user_id == user_id,
        Transaction.type == TransactionType.EXPENSE,
    )

    if start_date and end_date:
        query = query.where(Transaction.occurred_at.between(start_date, end_date))

    if wallet_id:
        query = query.where(Transaction.wallet_id == wallet_id)

    if category_id:
        query = query.where(Transaction.category_id == category_id)

    result = await db.execute(query.order_by(Transaction.occurred_at.desc()))
    return result.scalars().all()



async def get_expense(
    db: AsyncSession,
    user_id: int,
    expense_id: int,
):
    result = await db.execute(
        select(Transaction).where(
            Transaction.id == expense_id,
            Transaction.user_id == user_id,
            Transaction.type == TransactionType.EXPENSE,
        )
    )
    return result.scalar_one()


async def delete_expense(
    db: AsyncSession,
    user_id: int,
    expense_id: int,
):
    result = await db.execute(
        select(Transaction).where(
            Transaction.id == expense_id,
            Transaction.user_id == user_id,
            Transaction.type == TransactionType.EXPENSE,
        )
    )
    expense = result.scalar_one()

    result = await db.execute(
        select(Wallet).where(
            Wallet.id == expense.wallet_id,
            Wallet.user_id == user_id,
        )
    )
    wallet = result.scalar_one()

    wallet.balance += Decimal(expense.amount)
    await db.delete(expense)
    await db.commit()
