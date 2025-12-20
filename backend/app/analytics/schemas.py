from pydantic import BaseModel


class PeriodSummary(BaseModel):
    income: float
    expense: float
    profit: float


class MonthlyBreakdown(BaseModel):
    month: str
    income: float
    expense: float
    profit: float
