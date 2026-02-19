from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.permissions import require_psychologist
from app.crud.psychologist_profile import ensure_for_user, update_for_user
from app.db.deps import get_db
from app.models.user import User
from app.schemas.psychologist_profile import PsychologistProfileOut, PsychologistProfileUpdate

router = APIRouter(prefix="/psychologist", tags=["psychologist"])


@router.get("/me", response_model=PsychologistProfileOut)
async def get_my_psychologist_profile(
    session: AsyncSession = Depends(get_db),
    user: User = Depends(require_psychologist),
):
    return await ensure_for_user(session, user.id)


@router.patch("/me", response_model=PsychologistProfileOut)
async def update_my_psychologist_profile(
    data: PsychologistProfileUpdate,
    session: AsyncSession = Depends(get_db),
    user: User = Depends(require_psychologist),
):
    return await update_for_user(session, user.id, data)