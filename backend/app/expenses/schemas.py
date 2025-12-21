from pydantic import BaseModel
from datetime import datetime


class ExpenseCreate(BaseModel):
    wallet_id: int
    category_id: int
    amount: float
    occurred_at: datetime
    note: str | None = None


class ExpenseResponse(BaseModel):
    id: int
    amount: float
    occurred_at: datetime
    category_id: int
    wallet_id: int

class ExpenseUpdate(BaseModel):
    amount: float | None = None
    note: str | None = None
    occurred_at: datetime | None = None
    category_id: int | None = None
    wallet_id: int | None = None