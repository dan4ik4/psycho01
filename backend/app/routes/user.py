from sqlalchemy.ext.asyncio import AsyncSession
from fastapi import Depends, APIRouter

from app.db.deps import get_db
from app.schemas.user import UserUpdate, UserRead
from app.models.user import User
from app.auth.deps import current_active_user

router = APIRouter(prefix="/users", tags=["users"])

@router.patch("/me", response_model=UserRead)
async def update_me(
    data: UserUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
):
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(user, field, value)

    db.add(user)
    await db.commit()
    await db.refresh(user)

    return user

@router.get("/me", response_model=UserRead)
async def get_me(
    user: User = Depends(current_active_user),
):
    return user