from uuid import UUID

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import current_active_user as get_current_user
from app.db.deps import get_db
from app.schemas.profile import ProfileOut, ProfileUpdate
from app.crud.profile import ensure_for_user, update_for_user
from app.models.user import User

router = APIRouter(prefix="/profile", tags=["profile"])


@router.get("/me", response_model=ProfileOut)
async def read_my_profile(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return await ensure_for_user(db, current_user.id)


@router.patch("/me", response_model=ProfileOut)
async def patch_my_profile(
    payload: ProfileUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return await update_for_user(db, current_user.id, payload)