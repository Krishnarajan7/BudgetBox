import re
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, field_validator

MONTH_RE = re.compile(r"^\d{4}-(0[1-9]|1[0-2])$")


def _validate_month(value: str) -> str:
    if not MONTH_RE.match(value):
        raise ValueError("month must be in YYYY-MM format")
    return value


class BudgetCreate(BaseModel):
    category_id: int
    month: str
    limit: Decimal

    @field_validator("month")
    @classmethod
    def check_month(cls, v: str) -> str:
        return _validate_month(v)

    @field_validator("limit")
    @classmethod
    def check_limit(cls, v: Decimal) -> Decimal:
        if v <= 0:
            raise ValueError("limit must be greater than 0")
        return v


class BudgetUpdate(BaseModel):
    limit: Optional[Decimal] = None

    @field_validator("limit")
    @classmethod
    def check_limit(cls, v: Optional[Decimal]) -> Optional[Decimal]:
        if v is not None and v <= 0:
            raise ValueError("limit must be greater than 0")
        return v


class BudgetResponse(BaseModel):
    id: int
    category_id: int
    month: str
    limit: float

    class Config:
        from_attributes = True


class BudgetUsageResponse(BaseModel):
    id: int
    category_id: int
    category_name: str
    month: str
    limit: float
    spent: float
    remaining: float
    percent_used: float
