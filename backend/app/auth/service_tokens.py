from datetime import datetime, timezone
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, delete

from app.models.refresh_token import RefreshToken
from app.auth.security import create_access_token, hash_token


async def refresh_access_token(
    db: AsyncSession,
    refresh_token: str,
) -> str | None:
    result = await db.execute(
        select(RefreshToken).where(
            RefreshToken.token_hash == hash_token(refresh_token),
            RefreshToken.expires_at > datetime.now(timezone.utc),
        )
    )
    token = result.scalar_one_or_none()

    if not token:
        return None

    return create_access_token(token.user_id)


async def logout(
    db: AsyncSession,
    refresh_token: str,
) -> None:
    await db.execute(
        delete(RefreshToken).where(
            RefreshToken.token_hash == hash_token(refresh_token)
        )
    )
    await db.commit()

async def logout_all_sessions(
    db: AsyncSession,
    user_id: int,
) -> None:
    await db.execute(
        delete(RefreshToken).where(
            RefreshToken.user_id == user_id
        )
    )
    await db.commit()