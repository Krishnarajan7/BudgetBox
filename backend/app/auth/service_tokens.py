from datetime import datetime, timezone
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, delete

from app.models.refresh_token import RefreshToken
from app.models.user import User
from app.auth.security import create_access_token, hash_token


async def refresh_access_token(
    db: AsyncSession,
    refresh_token: str,
) -> str | None:
    now = datetime.now(timezone.utc)

    result = await db.execute(
        select(RefreshToken).where(
            RefreshToken.token_hash == hash_token(refresh_token),
            RefreshToken.expires_at > now,
        )
    )
    token = result.scalar_one_or_none()

    if not token:
        return None

    user = await db.get(User, token.user_id)

    if not user or not user.is_active:
        return None

    # Opportunistically prune this user's expired refresh tokens. Session
    # synchronization is skipped because SQLite (used in tests) returns
    # naive datetimes for `expires_at`, which the ORM's in-python
    # synchronize_session="evaluate" strategy cannot compare against the
    # timezone-aware `now` used here.
    await db.execute(
        delete(RefreshToken)
        .where(
            RefreshToken.user_id == token.user_id,
            RefreshToken.expires_at < now,
        )
        .execution_options(synchronize_session=False)
    )
    await db.commit()

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