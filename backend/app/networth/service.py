from decimal import Decimal
from typing import Optional

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.core.errors import AppError
from app.models.asset import Asset, AssetKind
from app.models.wallet import Wallet


async def _get_asset_or_404(db: AsyncSession, user_id: int, asset_id: int) -> Asset:
    result = await db.execute(
        select(Asset).where(
            Asset.id == asset_id,
            Asset.user_id == user_id,
        )
    )
    asset = result.scalar_one_or_none()
    if not asset:
        raise AppError("ASSET_NOT_FOUND", "Asset not found", 404)
    return asset


async def create_asset(
    db: AsyncSession,
    user_id: int,
    name: str,
    kind: AssetKind,
    category: str,
    value: float,
    note: Optional[str] = None,
) -> Asset:
    asset = Asset(
        user_id=user_id,
        name=name,
        kind=kind,
        category=category,
        value=Decimal(str(value)),
        note=note,
    )
    db.add(asset)
    await db.commit()
    await db.refresh(asset)
    return asset


async def list_assets(db: AsyncSession, user_id: int):
    result = await db.execute(
        select(Asset).where(Asset.user_id == user_id).order_by(Asset.id)
    )
    return result.scalars().all()


async def update_asset(
    db: AsyncSession,
    user_id: int,
    asset_id: int,
    name: Optional[str] = None,
    kind: Optional[AssetKind] = None,
    category: Optional[str] = None,
    value: Optional[float] = None,
    note: Optional[str] = None,
) -> Asset:
    asset = await _get_asset_or_404(db, user_id, asset_id)

    if name is not None:
        asset.name = name
    if kind is not None:
        asset.kind = kind
    if category is not None:
        asset.category = category
    if value is not None:
        asset.value = Decimal(str(value))
    if note is not None:
        asset.note = note

    await db.commit()
    await db.refresh(asset)
    return asset


async def delete_asset(db: AsyncSession, user_id: int, asset_id: int):
    asset = await _get_asset_or_404(db, user_id, asset_id)
    await db.delete(asset)
    await db.commit()


async def get_net_worth(db: AsyncSession, user_id: int):
    wallets_result = await db.execute(
        select(Wallet).where(Wallet.user_id == user_id).order_by(Wallet.id)
    )
    wallets = wallets_result.scalars().all()

    assets_result = await db.execute(
        select(Asset).where(Asset.user_id == user_id).order_by(Asset.id)
    )
    all_assets = assets_result.scalars().all()

    assets = [a for a in all_assets if a.kind == AssetKind.ASSET]
    liabilities = [a for a in all_assets if a.kind == AssetKind.LIABILITY]

    wallets_total = sum((w.balance for w in wallets), Decimal("0.00"))
    assets_total = sum((a.value for a in assets), Decimal("0.00"))
    liabilities_total = sum((a.value for a in liabilities), Decimal("0.00"))
    net_worth = wallets_total + assets_total - liabilities_total

    return {
        "wallets_total": wallets_total,
        "assets_total": assets_total,
        "liabilities_total": liabilities_total,
        "net_worth": net_worth,
        "breakdown": {
            "wallets": wallets,
            "assets": assets,
            "liabilities": liabilities,
        },
    }
