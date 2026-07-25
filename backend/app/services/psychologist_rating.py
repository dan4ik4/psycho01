import uuid

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.crud.psychologist_rating import (
    get_psychologist_rating_summary,
    recalculate_psychologist_rating_cache,
    upsert_psychologist_rating,
)
from app.models.user import User
from app.schemas.psychologist_rating import PsychologistRatingSummary


async def rate_psychologist_service(
    db: AsyncSession,
    *,
    patient: User,
    psychologist_id: uuid.UUID,
    rating: int,
    comment: str | None,
):
    
    if patient.is_psychologist:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only patients can rate psychologists",
        )

    result = await db.execute(
        select(User).where(User.id == psychologist_id)
    )
    psychologist = result.scalar_one_or_none()

    if (
        psychologist is None
        or not psychologist.is_psychologist
        or not psychologist.is_active
    ):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Psychologist not found",
        )

    rating_record = await upsert_psychologist_rating(
        db,
        patient_id=patient.id,
        psychologist_id=psychologist_id,
        rating=rating,
        comment=comment,
    )

    await recalculate_psychologist_rating_cache(
        db,
        psychologist=psychologist,
    )

    await db.commit()
    await db.refresh(rating_record)

    return rating_record


async def get_psychologist_rating_summary_service(
    db: AsyncSession,
    *,
    psychologist_id: uuid.UUID,
) -> PsychologistRatingSummary:
    average_rating, ratings_count = await get_psychologist_rating_summary(
        db,
        psychologist_id=psychologist_id,
    )

    return PsychologistRatingSummary(
        psychologist_id=psychologist_id,
        average_rating=round(float(average_rating), 2) if average_rating is not None else None,
        ratings_count=ratings_count,
    )