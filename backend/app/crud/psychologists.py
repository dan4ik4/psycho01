from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User


async def get_psychologists(
    db: AsyncSession,
) -> list[User]:
    result = await db.execute(
        select(User)
        .where(
            User.is_psychologist.is_(True),
            User.is_active.is_(True),
        )
        .order_by(
            User.last_name.asc().nulls_last(),
            User.first_name.asc().nulls_last(),
            User.id.asc(),
        )
    )

    return list(result.scalars().all())