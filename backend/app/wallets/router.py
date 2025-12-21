from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.auth.deps import get_current_user
from app.models.user import User

from app.wallets.schemas import WalletCreate, WalletUpdate, WalletResponse
from app.wallets.service import (
    create_wallet,
    list_wallets,
    update_wallet,
    delete_wallet,
)

router = APIRouter(prefix="/wallets", tags=["wallets"])


@router.post("", response_model=WalletResponse, status_code=status.HTTP_201_CREATED)
async def create(
    data: WalletCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await create_wallet(db, user.id, data.name, data.balance)


@router.get("", response_model=list[WalletResponse])
async def list_all(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await list_wallets(db, user.id)


@router.patch("/{wallet_id}", response_model=WalletResponse)
async def update(
    wallet_id: int,
    data: WalletUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await update_wallet(
        db,
        user.id,
        wallet_id,
        name=data.name,
        balance=data.balance,
    )


@router.delete("/{wallet_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete(
    wallet_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await delete_wallet(db, user.id, wallet_id)
