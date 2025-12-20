from fastapi import APIRouter, Depends
from datetime import date, timedelta

from sqlalchemy.ext.asyncio import AsyncSession

from app.analytics.service import summary_by_period, top_expense_categories, yearly_breakdown,dashboard_summary, month_comparison
from app.core.database import get_db
from app.auth.deps import get_current_user
from app.models.user import User

router = APIRouter(prefix="/analytics", tags=["analytics"])


@router.get("/weekly")
async def weekly_summary(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    today = date.today()
    start = today - timedelta(days=7)

    return await summary_by_period(db, user.id, start, today)


@router.get("/monthly")
async def monthly_summary(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    today = date.today()
    start = today.replace(day=1)

    return await summary_by_period(db, user.id, start, today)


@router.get("/yearly/{year}")
async def yearly_summary(
    year: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await yearly_breakdown(db, user.id, year)
  
@router.get("/top-categories")
async def top_categories(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await top_expense_categories(db, user.id)

@router.get("/dashboard")
async def dashboard(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await dashboard_summary(db, user.id)

@router.get("/compare/monthly")
async def monthly_comparison(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await month_comparison(db, user.id)
