import uuid

from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.psychologist_rating import PsychologistRating


async def get_rating_by_patient_and_psychologist(
    db: AsyncSession,
    *,
    patient_id: uuid.UUID,
    psychologist_id: uuid.UUID,
) -> PsychologistRating | None:
    result = await db.execute(
        select(PsychologistRating).where(
            PsychologistRating.patient_id == patient_id,
            PsychologistRating.psychologist_id == psychologist_id,
        )
    )
    return result.scalar_one_or_none()


async def upsert_psychologist_rating(
    db: AsyncSession,
    *,
    patient_id: uuid.UUID,
    psychologist_id: uuid.UUID,
    rating: int,
    comment: str | None,
) -> PsychologistRating:
    existing_rating = await get_rating_by_patient_and_psychologist(
        db,
        patient_id=patient_id,
        psychologist_id=psychologist_id,
    )

    if existing_rating:
        existing_rating.rating = rating
        existing_rating.comment = comment

        db.add(existing_rating)
        await db.commit()
        await db.refresh(existing_rating)

        return existing_rating

    new_rating = PsychologistRating(
        patient_id=patient_id,
        psychologist_id=psychologist_id,
        rating=rating,
        comment=comment,
    )

    db.add(new_rating)
    await db.commit()
    await db.refresh(new_rating)

    return new_rating


async def get_psychologist_rating_summary(
    db: AsyncSession,
    *,
    psychologist_id: uuid.UUID,
) -> tuple[float | None, int]:
    last_50_ratings_subquery = (
        select(PsychologistRating.rating)
        .where(PsychologistRating.psychologist_id == psychologist_id)
        .order_by(PsychologistRating.updated_at.desc())
        .limit(50)
        .subquery()
    )

    result = await db.execute(
        select(
            func.avg(last_50_ratings_subquery.c.rating),
            func.count(last_50_ratings_subquery.c.rating),
        )
    )

    average_rating, ratings_count = result.one()

    return average_rating, ratings_count