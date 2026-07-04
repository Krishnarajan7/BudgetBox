from datetime import date as _date, datetime, timedelta
from decimal import Decimal
from typing import Optional

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.core.errors import AppError
from app.models.category import Category, CategoryType
from app.models.transaction import Transaction, TransactionType
from app.models.wallet import Wallet


async def _get_wallet_or_404(db: AsyncSession, user_id: int, wallet_id: int) -> Wallet:
    result = await db.execute(
        select(Wallet).where(
            Wallet.id == wallet_id,
            Wallet.user_id == user_id,
        )
    )
    wallet = result.scalar_one_or_none()
    if not wallet:
        raise AppError("WALLET_NOT_FOUND", "Wallet not found", 404)
    return wallet


async def _get_expense_category_or_404(
    db: AsyncSession, user_id: int, category_id: int
) -> Category:
    result = await db.execute(
        select(Category).where(
            Category.id == category_id,
            Category.user_id == user_id,
            Category.type == CategoryType.EXPENSE,
        )
    )
    category = result.scalar_one_or_none()
    if not category:
        raise AppError("CATEGORY_NOT_FOUND", "Category not found", 404)
    return category


async def _get_expense_or_404(
    db: AsyncSession, user_id: int, expense_id: int
) -> Transaction:
    result = await db.execute(
        select(Transaction).where(
            Transaction.id == expense_id,
            Transaction.user_id == user_id,
            Transaction.type == TransactionType.EXPENSE,
        )
    )
    expense = result.scalar_one_or_none()
    if not expense:
        raise AppError("EXPENSE_NOT_FOUND", "Expense not found", 404)
    return expense


async def create_expense(
    db: AsyncSession,
    user_id: int,
    data,
) -> Transaction:
    wallet = await _get_wallet_or_404(db, user_id, data.wallet_id)
    await _get_expense_category_or_404(db, user_id, data.category_id)

    amount = Decimal(str(data.amount))

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
    expense = await _get_expense_or_404(db, user_id, expense_id)
    wallet = await _get_wallet_or_404(db, user_id, expense.wallet_id)

    if data.category_id is not None:
        await _get_expense_category_or_404(db, user_id, data.category_id)

    old_amount = Decimal(expense.amount)
    new_amount = Decimal(str(data.amount)) if data.amount is not None else old_amount

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
    start_date: Optional[_date] = None,
    end_date: Optional[_date] = None,
    wallet_id: Optional[int] = None,
    category_id: Optional[int] = None,
):
    query = select(Transaction).where(
        Transaction.user_id == user_id,
        Transaction.type == TransactionType.EXPENSE,
    )

    if start_date and end_date:
        start_datetime = datetime.combine(start_date, datetime.min.time())
        end_datetime_exclusive = datetime.combine(end_date, datetime.min.time()) + timedelta(days=1)
        query = query.where(
            Transaction.occurred_at >= start_datetime,
            Transaction.occurred_at < end_datetime_exclusive,
        )

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
    return await _get_expense_or_404(db, user_id, expense_id)


async def delete_expense(
    db: AsyncSession,
    user_id: int,
    expense_id: int,
):
    expense = await _get_expense_or_404(db, user_id, expense_id)
    wallet = await _get_wallet_or_404(db, user_id, expense.wallet_id)

    wallet.balance += Decimal(expense.amount)
    await db.delete(expense)
    await db.commit()
