from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, Field

from app.models.asset import AssetKind


class AssetCreate(BaseModel):
    name: str
    kind: AssetKind
    category: str
    value: float = Field(gt=0)
    note: Optional[str] = None


class AssetUpdate(BaseModel):
    name: Optional[str] = None
    kind: Optional[AssetKind] = None
    category: Optional[str] = None
    value: Optional[float] = Field(default=None, gt=0)
    note: Optional[str] = None


class AssetResponse(BaseModel):
    id: int
    name: str
    kind: AssetKind
    category: str
    value: Decimal
    note: Optional[str] = None

    class Config:
        from_attributes = True


class WalletBreakdown(BaseModel):
    id: int
    name: str
    balance: Decimal

    class Config:
        from_attributes = True


class AssetBreakdown(BaseModel):
    id: int
    name: str
    category: str
    value: Decimal

    class Config:
        from_attributes = True


class NetWorthBreakdown(BaseModel):
    wallets: list[WalletBreakdown]
    assets: list[AssetBreakdown]
    liabilities: list[AssetBreakdown]


class NetWorthResponse(BaseModel):
    wallets_total: Decimal
    assets_total: Decimal
    liabilities_total: Decimal
    net_worth: Decimal
    breakdown: NetWorthBreakdown
