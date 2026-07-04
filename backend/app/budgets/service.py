import re
from datetime import date
from decimal import Decimal
from typing import Optional

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func

from app.core.errors import AppError
from app.models.budget import Budget
from app.models.category import Category, CategoryType
from app.models.transaction import Transaction, TransactionType

MONTH_RE = re.compile(r"^\d{4}-(0[1-9]|1[0-2])$")


def month_bounds(month: str) -> tuple[date, date]:
    """Validate a "YYYY-MM" string and return (start, next_month_start) dates.

    Raises AppError if the format is invalid.
    """
    if not MONTH_RE.match(month):
        raise AppError("INVALID_MONTH", "Month must be in YYYY-MM format", 400)

    year, mon = (int(part) for part in month.split("-"))
    start = date(year, mon, 1)
    if mon == 12:
        next_start = date(year + 1, 1, 1)
    else:
        next_start = date(year, mon + 1, 1)
    return start, next_start


async def _get_expense_category(
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
    if category.type != CategoryType.EXPENSE:
        raise AppError(
            "CATEGORY_TYPE_MISMATCH",
            "Category is not an expense category",
            400,
        )
    return category


async def create_budget(
    db: AsyncSession,
    user_id: int,
    category_id: int,
    month: str,
    limit: Decimal,
) -> Budget:
    month_bounds(month)  # validates format, raises AppError if malformed

    await _get_expense_category(db, user_id, category_id)

    existing = await db.execute(
        select(Budget).where(
            Budget.user_id == user_id,
            Budget.category_id == category_id,
            Budget.month == month,
        )
    )
    if existing.scalar_one_or_none():
        raise AppError(
            "BUDGET_ALREADY_EXISTS",
            "A budget already exists for this category and month",
            409,
        )

    budget = Budget(
        user_id=user_id,
        category_id=category_id,
        month=month,
        limit=limit,
    )
    db.add(budget)
    await db.commit()
    await db.refresh(budget)
    return budget


async def list_budgets_with_usage(
    db: AsyncSession,
    user_id: int,
    month: str,
) -> list[dict]:
    start, next_start = month_bounds(month)

    result = await db.execute(
        select(Budget, Category.name)
        .join(Category, Category.id == Budget.category_id)
        .where(
            Budget.user_id == user_id,
            Budget.month == month,
        )
        .order_by(Category.name)
    )
    rows = result.all()

    if not rows:
        return []

    category_ids = [budget.category_id for budget, _ in rows]

    spent_result = await db.execute(
        select(
            Transaction.category_id,
            func.sum(Transaction.amount),
        )
        .where(
            Transaction.user_id == user_id,
            Transaction.type == TransactionType.EXPENSE,
            Transaction.category_id.in_(category_ids),
            Transaction.occurred_at >= start,
            Transaction.occurred_at < next_start,
        )
        .group_by(Transaction.category_id)
    )
    spent_map = {cat_id: float(total or 0) for cat_id, total in spent_result.all()}

    items = []
    for budget, category_name in rows:
        limit = float(budget.limit)
        spent = spent_map.get(budget.category_id, 0.0)
        remaining = limit - spent
        percent_used = (spent / limit * 100) if limit > 0 else 0.0
        items.append(
            {
                "id": budget.id,
                "category_id": budget.category_id,
                "category_name": category_name,
                "month": budget.month,
                "limit": limit,
                "spent": spent,
                "remaining": remaining,
                "percent_used": percent_used,
            }
        )
    return items


async def get_budget(db: AsyncSession, user_id: int, budget_id: int) -> Budget:
    result = await db.execute(
        select(Budget).where(
            Budget.id == budget_id,
            Budget.user_id == user_id,
        )
    )
    budget = result.scalar_one_or_none()
    if not budget:
        raise AppError("BUDGET_NOT_FOUND", "Budget not found", 404)
    return budget


async def update_budget(
    db: AsyncSession,
    user_id: int,
    budget_id: int,
    limit: Optional[Decimal] = None,
) -> Budget:
    budget = await get_budget(db, user_id, budget_id)

    if limit is not None:
        budget.limit = limit

    await db.commit()
    await db.refresh(budget)
    return budget


async def delete_budget(db: AsyncSession, user_id: int, budget_id: int):
    budget = await get_budget(db, user_id, budget_id)
    await db.delete(budget)
    await db.commit()
