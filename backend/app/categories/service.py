from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import Optional

from app.models.category import Category, CategoryType
from app.core.errors import AppError


async def create_category(
    db: AsyncSession,
    user_id: int,
    name: str,
    type: CategoryType,
) -> Category:
    category = Category(user_id=user_id, name=name, type=type)
    db.add(category)
    await db.commit()
    await db.refresh(category)
    return category


async def list_categories(
    db: AsyncSession,
    user_id: int,
    type: Optional[CategoryType] = None,
):
    query = select(Category).where(Category.user_id == user_id)
    if type is not None:
        query = query.where(Category.type == type)
    result = await db.execute(query.order_by(Category.name))
    return result.scalars().all()


async def update_category(
    db: AsyncSession,
    user_id: int,
    category_id: int,
    name: Optional[str] = None,
    type: Optional[CategoryType] = None,
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

    if name is not None:
        category.name = name
    if type is not None:
        category.type = type

    await db.commit()
    await db.refresh(category)
    return category


async def delete_category(
    db: AsyncSession,
    user_id: int,
    category_id: int,
):
    result = await db.execute(
        select(Category).where(
            Category.id == category_id,
            Category.user_id == user_id,
        )
    )
    category = result.scalar_one_or_none()
    if not category:
        raise AppError("CATEGORY_NOT_FOUND", "Category not found", 404)
    await db.delete(category)
    await db.commit()
