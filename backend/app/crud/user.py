from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
import uuid

from app.models.user import User


async def get_user_by_email(
    db: AsyncSession,
    email: str,
) -> User | None:
    result = await db.execute(
        select(User).where(User.email == email)
    )
    return result.scalar_one_or_none()

async def create_user(
    db: AsyncSession,
    *,
    email: str,
    hashed_password: str,
) -> User:
    user = User(
        email=email,
        hashed_password=hashed_password,
        is_active=True,
        is_verified=True,
    )

    db.add(user)
    await db.flush()
    await db.refresh(user)

    return user

async def get_user_by_id(
    db: AsyncSession,
    user_id: uuid.UUID,
) -> User | None:
    result = await db.execute(
        select(User).where(User.id == user_id)
    )

    return result.scalar_one_or_none()