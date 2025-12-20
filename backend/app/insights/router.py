from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.auth.deps import get_current_user
from app.models.user import User
from app.insights.service import weekly_insight

router = APIRouter(prefix="/insights", tags=["insights"])


@router.get("/weekly")
async def weekly(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return await weekly_insight(db, user.id)
