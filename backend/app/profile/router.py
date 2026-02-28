from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.auth.deps import get_current_user
from app.profile.service import get_profile, update_profile
from app.profile.schemas import ProfileUpdate
from app.profile.stats_service import profile_stats
from app.profile.activity_service import activity_heatmap

router = APIRouter(prefix="/profile", tags=["profile"])


@router.get("")
async def profile(
    db: AsyncSession = Depends(get_db),
    user=Depends(get_current_user),
):
    profile = await get_profile(db, user)
    stats = await profile_stats(db, user.id)
    heatmap = await activity_heatmap(db, user.id)

    return {
        "profile": profile,
        "stats": stats,
        "activity": heatmap,
    }


@router.put("")
async def update(
    data: ProfileUpdate,
    db: AsyncSession = Depends(get_db),
    user=Depends(get_current_user),
):
    return await update_profile(db, user, data)
