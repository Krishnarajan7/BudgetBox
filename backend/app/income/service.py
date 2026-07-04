from decimal import Decimal
from datetime import date as _date, timedelta
from typing import Optional

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.core.errors import AppError
from app.models.transaction import Transaction, TransactionType
from app.models.wallet import Wallet
from app.models.category import Category, CategoryType


async def _validate_income_category(
    db: AsyncSession,
    user_id: int,
    category_id: int,
) -> Category:
    result = await db.execute(
        select(Category).where(
            Category.id == category_id,
            Category.user_id == user_id,
        )
    )
    category = result.scalar_one_or_none()
    if not category:
        raise AppError("CATEGORY_NOT_FOUND", "Category not found", 404)
    if category.type != CategoryType.INCOME:
        raise AppError(
            "CATEGORY_TYPE_MISMATCH",
            "Category is not an income category",
            400,
        )
    return category


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
        raise AppError("WALLET_NOT_FOUND", "Wallet not found", 404)

    await _validate_income_category(db, user_id, data.category_id)

    amount = Decimal(str(data.amount))

    income = Transaction(
        user_id=user_id,
        wallet_id=wallet.id,
        category_id=data.category_id,
        type=TransactionType.INCOME,
        amount=amount,
        occurred_at=data.occurred_at,
        note=data.note,
    )

    wallet.balance += amount

    db.add(income)
    await db.commit()
    await db.refresh(income)
    return income


async def list_incomes(
    db: AsyncSession,
    user_id: int,
    start_date: Optional[_date] = None,
    end_date: Optional[_date] = None,
    wallet_id: Optional[int] = None,
    category_id: Optional[int] = None,
):
    query = select(Transaction).where(
        Transaction.user_id == user_id,
        Transaction.type == TransactionType.INCOME,
    )

    if start_date and end_date:
        query = query.where(
            Transaction.occurred_at >= start_date,
            Transaction.occurred_at < end_date + timedelta(days=1),
        )
    if wallet_id:
        query = query.where(Transaction.wallet_id == wallet_id)
    if category_id:
        query = query.where(Transaction.category_id == category_id)

    result = await db.execute(query.order_by(Transaction.occurred_at.desc()))
    return result.scalars().all()


async def get_income(
    db: AsyncSession,
    user_id: int,
    income_id: int,
) -> Transaction:
    result = await db.execute(
        select(Transaction).where(
            Transaction.id == income_id,
            Transaction.user_id == user_id,
            Transaction.type == TransactionType.INCOME,
        )
    )
    income = result.scalar_one_or_none()
    if not income:
        raise AppError("INCOME_NOT_FOUND", "Income not found", 404)
    return income


async def update_income(
    db: AsyncSession,
    user_id: int,
    income_id: int,
    data,
) -> Transaction:
    income = await get_income(db, user_id, income_id)
    wallet = await db.get(Wallet, income.wallet_id)

    old_amount = Decimal(income.amount)

    if data.amount is not None:
        new_amount = Decimal(str(data.amount))
        wallet.balance -= old_amount
        wallet.balance += new_amount
        income.amount = new_amount

    if data.category_id is not None:
        await _validate_income_category(db, user_id, data.category_id)
        income.category_id = data.category_id

    if data.note is not None:
        income.note = data.note

    if data.occurred_at is not None:
        income.occurred_at = data.occurred_at

    if data.wallet_id is not None and data.wallet_id != income.wallet_id:
        new_wallet_result = await db.execute(
            select(Wallet).where(
                Wallet.id == data.wallet_id,
                Wallet.user_id == user_id,
            )
        )
        new_wallet = new_wallet_result.scalar_one_or_none()
        if not new_wallet:
            raise AppError("WALLET_NOT_FOUND", "Wallet not found", 404)
        # revert old wallet, apply to new
        wallet.balance -= Decimal(income.amount)
        new_wallet.balance += Decimal(income.amount)
        income.wallet_id = new_wallet.id

    await db.commit()
    await db.refresh(income)
    return income


async def delete_income(
    db: AsyncSession,
    user_id: int,
    income_id: int,
):
    income = await get_income(db, user_id, income_id)
    wallet = await db.get(Wallet, income.wallet_id)
    if wallet:
        wallet.balance -= Decimal(income.amount)
    await db.delete(income)
    await db.commit()
