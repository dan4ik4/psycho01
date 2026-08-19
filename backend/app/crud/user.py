import uuid

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.email import normalize_email
from app.models.user import User


async def get_user_by_email(
    db: AsyncSession,
    email: str,
) -> User | None:
    normalized_email = normalize_email(email)

    result = await db.execute(
        select(User).where(
            func.lower(User.email) == normalized_email
        )
    )

    return result.scalar_one_or_none()


async def create_user(
    db: AsyncSession,
    *,
    email: str,
    hashed_password: str,
) -> User:
    user = User(
        email=normalize_email(email),
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
    *,
    for_update: bool = False,
) -> User | None:
    query = select(User).where(User.id == user_id)

    if for_update:
        query = (
            query
            .with_for_update()
            .execution_options(
                populate_existing=True,
            )
        )

    result = await db.execute(query)

    return result.scalar_one_or_none()