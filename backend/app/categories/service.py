from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.models.category import Category


async def create_category(db: AsyncSession, user_id: int, name: str):
    category = Category(user_id=user_id, name=name)
    db.add(category)
    await db.commit()
    await db.refresh(category)
    return category


async def list_categories(db: AsyncSession, user_id: int):
    result = await db.execute(
        select(Category).where(Category.user_id == user_id)
    )
    return result.scalars().all()


async def update_category(
    db: AsyncSession,
    user_id: int,
    category_id: int,
    name: str,
):
    result = await db.execute(
        select(Category).where(
            Category.id == category_id,
            Category.user_id == user_id,
        )
    )
    category = result.scalar_one()
    category.name = name
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
    category = result.scalar_one()
    await db.delete(category)
    await db.commit()
