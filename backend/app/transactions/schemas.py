from datetime import datetime
from pydantic import BaseModel

from app.models.transaction import TransactionType


class TransactionResponse(BaseModel):
    id: int
    type: TransactionType
    amount: float
    wallet_id: int
    category_id: int
    note: str | None
    occurred_at: datetime

    class Config:
        from_attributes = True


class TransactionListResponse(BaseModel):
    total: int
    limit: int
    offset: int
    items: list[TransactionResponse]
