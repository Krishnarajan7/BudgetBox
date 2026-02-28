from datetime import date
from sqlalchemy import select
from app.models.user_profile import UserProfile
from app.profile.schemas import ProfileResponse
from app.core.errors import AppError


async def get_profile(db, user) -> ProfileResponse:
    result = await db.execute(
        select(UserProfile).where(UserProfile.user_id == user.id)
    )
    profile = result.scalar_one_or_none()

    if not profile:
        profile = UserProfile(
            user_id=user.id,
            first_name="",
            last_name="",
            timezone="UTC",
            join_date=date.today(),
        )
        db.add(profile)
        await db.commit()
        await db.refresh(profile)

    return ProfileResponse(
        first_name=profile.first_name,
        last_name=profile.last_name,
        email=user.email,
        phone=profile.phone,
        location=profile.location,
        occupation=profile.occupation,
        website=profile.website,
        bio=profile.bio,
        timezone=profile.timezone,
        avatar_url=profile.avatar_url,
        join_date=profile.join_date,
    )


async def update_profile(db, user, data) -> ProfileResponse:
    result = await db.execute(
        select(UserProfile).where(UserProfile.user_id == user.id)
    )
    profile = result.scalar_one_or_none()

    if not profile:
        raise AppError("Profile not found", 404)

    update_data = data.model_dump(exclude_unset=True)

    for field, value in update_data.items():
        setattr(profile, field, value)

    await db.commit()
    await db.refresh(profile)

    return ProfileResponse(
        first_name=profile.first_name,
        last_name=profile.last_name,
        email=user.email,
        phone=profile.phone,
        location=profile.location,
        occupation=profile.occupation,
        website=profile.website,
        bio=profile.bio,
        timezone=profile.timezone,
        avatar_url=profile.avatar_url,
        join_date=profile.join_date,
    )

async def get_join_date(db, user) -> date:
    result = await db.execute(
        select(UserProfile.join_date).where(UserProfile.user_id == user.id)
    )
    join_date = result.scalar_one_or_none()

    if not join_date:
        raise AppError("Profile not found", 404)

    return join_date

