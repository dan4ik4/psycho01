from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.deps import get_db
from app.models.user import User
from app.schemas.user import UserRead, PsychologistUpdate
from app.auth.deps import require_psychologist

router = APIRouter(prefix="/psychologist", tags=["psychologist"])

@router.get("/me", response_model=UserRead)
async def get_my_psychologist_profile(
    user: User = Depends(require_psychologist),
):
    return user


@router.patch("/me", response_model=UserRead)
async def update_my_psychologist_profile(
    data: PsychologistUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_psychologist),
):
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(user, field, value)

    db.add(user)
    await db.commit()
    await db.refresh(user)

    return user