from pydantic import BaseModel
from datetime import datetime


class IncomeCreate(BaseModel):
    wallet_id: int
    category_id: int
    amount: float
    occurred_at: datetime
    note: str | None = None


class IncomeResponse(BaseModel):
    id: int
    amount: float
    occurred_at: datetime
    wallet_id: int
    category_id: int
    note: str | None = None
    


class IncomeUpdate(BaseModel):
    amount: float | None = None
    note: str | None = None
    occurred_at: datetime | None = None
    category_id: int | None = None
    wallet_id: int | None = None