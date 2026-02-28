import asyncio
from sqlalchemy import select

from app.core.database import AsyncSessionLocal
from app.models.user import User
from app.auth.security import hash_password


async def seed_user():
    async with AsyncSessionLocal() as db:
        email = "test@budgetbox.com"
        password = "password123"

        result = await db.execute(
            select(User).where(User.email == email)
        )
        user = result.scalar_one_or_none()

        if user:
            print("User already exists")
            return

        user = User(
            email=email,
            password_hash=hash_password(password),
            is_active=True,
            is_verified=True,
        )

        db.add(user)
        await db.commit()
        await db.refresh(user)

        print("User seeded successfully")
        print(email)
        print(password)


if __name__ == "__main__":
    asyncio.run(seed_user())
