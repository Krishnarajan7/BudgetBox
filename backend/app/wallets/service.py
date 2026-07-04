from decimal import Decimal
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.core.errors import AppError
from app.models.wallet import Wallet


async def create_wallet(
    db: AsyncSession,
    user_id: int,
    name: str,
    balance: Decimal = Decimal("0.00"),
) -> Wallet:
    wallet = Wallet(
        user_id=user_id,
        name=name,
        balance=balance,
    )
    db.add(wallet)
    await db.commit()
    await db.refresh(wallet)
    return wallet


async def list_wallets(
    db: AsyncSession,
    user_id: int,
):
    result = await db.execute(
        select(Wallet).where(Wallet.user_id == user_id)
    )
    return result.scalars().all()


async def update_wallet(
    db: AsyncSession,
    user_id: int,
    wallet_id: int,
    name: str | None = None,
    balance: Decimal | None = None,
) -> Wallet:
    result = await db.execute(
        select(Wallet).where(
            Wallet.id == wallet_id,
            Wallet.user_id == user_id,
        )
    )
    wallet = result.scalar_one_or_none()
    if not wallet:
        raise AppError("WALLET_NOT_FOUND", "Wallet not found", 404)

    if name is not None:
        wallet.name = name

    if balance is not None:
        wallet.balance = balance  # manual correction allowed

    await db.commit()
    await db.refresh(wallet)
    return wallet


async def delete_wallet(
    db: AsyncSession,
    user_id: int,
    wallet_id: int,
):
    result = await db.execute(
        select(Wallet).where(
            Wallet.id == wallet_id,
            Wallet.user_id == user_id,
        )
    )
    wallet = result.scalar_one_or_none()
    if not wallet:
        raise AppError("WALLET_NOT_FOUND", "Wallet not found", 404)

    await db.delete(wallet)
    await db.commit()
