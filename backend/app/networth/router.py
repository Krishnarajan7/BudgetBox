from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.auth.deps import get_current_user
from app.models.user import User

from app.networth.schemas import (
    AssetCreate,
    AssetUpdate,
    AssetResponse,
    NetWorthResponse,
)
from app.networth.service import (
    create_asset,
    list_assets,
    update_asset,
    delete_asset,
    get_net_worth,
)

router = APIRouter(tags=["networth"])


@router.post("/assets", response_model=AssetResponse, status_code=status.HTTP_201_CREATED)
async def create(
    data: AssetCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await create_asset(
        db,
        user.id,
        data.name,
        data.kind,
        data.category,
        data.value,
        data.note,
    )


@router.get("/assets", response_model=list[AssetResponse])
async def list_all(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await list_assets(db, user.id)


@router.patch("/assets/{asset_id}", response_model=AssetResponse)
async def update(
    asset_id: int,
    data: AssetUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await update_asset(
        db,
        user.id,
        asset_id,
        name=data.name,
        kind=data.kind,
        category=data.category,
        value=data.value,
        note=data.note,
    )


@router.delete("/assets/{asset_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete(
    asset_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await delete_asset(db, user.id, asset_id)


@router.get("/networth", response_model=NetWorthResponse)
async def net_worth(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await get_net_worth(db, user.id)
