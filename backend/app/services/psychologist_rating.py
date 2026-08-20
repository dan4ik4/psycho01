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
from app.models.slot import Slot
from app.models.slot_event import SlotEvent, SlotEventType


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
        select(User)
        .where(User.id == psychologist_id)
        .with_for_update()
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
    
    completed_session_result = await db.execute(
        select(SlotEvent.id)
        .join(
            Slot,
            Slot.id == SlotEvent.slot_id,
        )
        .where(
            Slot.psychologist_id == psychologist_id,
            SlotEvent.patient_id == patient.id,
            SlotEvent.event_type == SlotEventType.COMPLETED,
        )
        .limit(1)
    )

    has_completed_session = (
        completed_session_result.scalar_one_or_none()
        is not None
    )

    if not has_completed_session:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=(
                "You can rate this psychologist only after "
                "a completed session"
            ),
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
    rating_summary = await get_psychologist_rating_summary(
        db,
        psychologist_id=psychologist_id,
    )

    if rating_summary is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Psychologist not found",
        )

    average_rating, ratings_count = rating_summary

    return PsychologistRatingSummary(
        psychologist_id=psychologist_id,
        average_rating=(
            round(float(average_rating), 2)
            if average_rating is not None
            else None
        ),
        ratings_count=ratings_count,
    )