from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
import uuid

from app.auth.deps import require_superuser
from app.db.deps import get_db
from app.models.user import User
from app.schemas.user import UserRead

router = APIRouter(prefix="/admin", tags=["admin"])

#switch to psychologist
@router.patch("/users/{user_id}/psychologist", response_model=UserRead)
async def toggle_psychologist(
    user_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(require_superuser),
):
    result = await db.execute(
        select(User).where(User.id == user_id)
    )
    user = result.scalar_one_or_none()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    user.is_psychologist = not user.is_psychologist

    db.add(user)
    await db.commit()
    await db.refresh(user)

    return user