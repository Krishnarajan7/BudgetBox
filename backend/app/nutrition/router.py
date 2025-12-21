from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from datetime import date

from app.core.database import get_db
from app.auth.deps import get_current_user
from app.models.user import User
from app.nutrition.service import daily_health_report, weekly_health_report

router = APIRouter(prefix="/nutrition", tags=["nutrition"])


@router.get("/daily")
async def get_daily_health_report(
    target_date: date | None = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await daily_health_report(
        db,
        user.id,
        target_date or date.today(),
    )


@router.get("/weekly")
async def get_weekly_health_report(
    end_date: date | None = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await weekly_health_report(
        db,
        user.id,
        end_date or date.today(),
    )
