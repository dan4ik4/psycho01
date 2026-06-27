import uuid

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import current_active_user
from app.db.deps import get_db
from app.models.user import User
from app.schemas.psychologist_rating import PsychologistRatingOut, PsychologistRatingUpsert, PsychologistRatingSummary
from app.services.psychologist_rating import rate_psychologist_service, get_psychologist_rating_summary_service

router = APIRouter(prefix="/psychologists_rating", tags=["psychologists_rating"])


@router.put("/{psychologist_id}/rating", response_model=PsychologistRatingOut)
async def rate_psychologist(
    psychologist_id: uuid.UUID,
    data: PsychologistRatingUpsert,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
):
    return await rate_psychologist_service(
        db=db,
        patient=user,
        psychologist_id=psychologist_id,
        rating=data.rating,
        comment=data.comment,
    )

@router.get("/{psychologist_id}/rating-summary", response_model=PsychologistRatingSummary)
async def get_rating_summary(
    psychologist_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
):
    return await get_psychologist_rating_summary_service(
        db=db,
        psychologist_id=psychologist_id,
    )