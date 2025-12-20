import secrets
from datetime import datetime, timedelta, timezone

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.user import User
from app.models.refresh_token import RefreshToken
from app.auth.security import (
    hash_password,
    verify_password,
    create_access_token,
    hash_token,
)

REFRESH_TOKEN_DAYS = 30


async def register_user(
    db: AsyncSession,
    email: str,
    password: str,
) -> User:
    result = await db.execute(select(User).where(User.email == email))
    if result.scalar_one_or_none():
        raise ValueError("Email already registered")

    user = User(
        email=email,
        password_hash=hash_password(password),
        is_active=True,
        is_verified=False,
    )

    db.add(user)
    await db.commit()
    await db.refresh(user)
    return user


async def authenticate_user(
    db: AsyncSession,
    email: str,
    password: str,
):
    result = await db.execute(select(User).where(User.email == email))
    user = result.scalar_one_or_none()

    if not user or not verify_password(password, user.password_hash):
        return None

    user.last_login_at = datetime.now(timezone.utc)

    access_token = create_access_token(user.id)

    raw_refresh = secrets.token_urlsafe(64)
    refresh = RefreshToken(
        user_id=user.id,
        token_hash=hash_token(raw_refresh),
        expires_at=datetime.now(timezone.utc)
        + timedelta(days=REFRESH_TOKEN_DAYS),
    )

    db.add(refresh)
    await db.commit()

    return access_token, raw_refresh
