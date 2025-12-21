from decimal import Decimal
from pydantic import BaseModel
from typing import Optional


class WalletCreate(BaseModel):
    name: str
    balance: Decimal = Decimal("0.00")


class WalletUpdate(BaseModel):
    name: Optional[str] = None
    balance: Optional[Decimal] = None


class WalletResponse(BaseModel):
    id: int
    name: str
    balance: Decimal

    class Config:
        from_attributes = True
