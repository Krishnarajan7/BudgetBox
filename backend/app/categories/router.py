from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Optional

from app.core.database import get_db
from app.auth.deps import get_current_user
from app.models.user import User
from app.models.category import CategoryType

from app.categories.schemas import (
    CategoryCreate,
    CategoryUpdate,
    CategoryResponse,
)
from app.categories.service import (
    create_category,
    list_categories,
    update_category,
    delete_category,
)

router = APIRouter(prefix="/categories", tags=["categories"])


@router.post("", response_model=CategoryResponse, status_code=status.HTTP_201_CREATED)
async def create(
    data: CategoryCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await create_category(db, user.id, data.name, data.type)


@router.get("", response_model=list[CategoryResponse])
async def list_all(
    type: Optional[CategoryType] = Query(None),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await list_categories(db, user.id, type)


@router.patch("/{category_id}", response_model=CategoryResponse)
async def update(
    category_id: int,
    data: CategoryUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await update_category(
        db, user.id, category_id, name=data.name, type=data.type
    )


@router.delete("/{category_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete(
    category_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await delete_category(db, user.id, category_id)
