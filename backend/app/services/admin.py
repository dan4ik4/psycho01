import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import (
    ConflictError,
    NotFoundError,
)
from app.crud.patient_assignment import (
    get_active_assignments,
    get_incoming_assignment_requests,
)
from app.crud.user import get_user_by_id
from app.models.user import User


async def toggle_psychologist(
    db: AsyncSession,
    user_id: uuid.UUID,
) -> User:
    user = await get_user_by_id(
        db=db,
        user_id=user_id,
        for_update=True,
    )

    if user is None:
        raise NotFoundError(
            "User not found"
        )

    if user.is_psychologist:
        active_assignments = await get_active_assignments(
            db=db,
            psychologist_id=user.id,
        )

        pending_assignments = await get_incoming_assignment_requests(
            db=db,
            psychologist_id=user.id,
        )

        if active_assignments or pending_assignments:
            raise ConflictError(
                "Psychologist role cannot be removed while "
                "there are active or pending assignments"
            )

    user.is_psychologist = not user.is_psychologist

    await db.commit()
    await db.refresh(user)

    return user