import uuid

from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.psychologist_rating import PsychologistRating
from app.models.user import User


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
        await db.flush()

        return existing_rating

    new_rating = PsychologistRating(
        patient_id=patient_id,
        psychologist_id=psychologist_id,
        rating=rating,
        comment=comment,
    )

    db.add(new_rating)
    await db.flush()
    await db.refresh(new_rating)

    return new_rating


async def get_psychologist_rating_summary(
    db: AsyncSession,
    *,
    psychologist_id: uuid.UUID,
) -> tuple[float | None, int] | None:
    result = await db.execute(
        select(
            User.average_rating,
            User.ratings_count,
        ).where(
            User.id == psychologist_id,
            User.is_psychologist.is_(True),
            User.is_active.is_(True),
        )
    )

    rating_data = result.one_or_none()

    if rating_data is None:
        return None

    average_rating, ratings_count = rating_data

    return (
        float(average_rating)
        if average_rating is not None
        else None,
        ratings_count,
    )

async def recalculate_psychologist_rating_cache(
    db: AsyncSession,
    *,
    psychologist: User,
) -> None:
    last_50_ratings_subquery = (
        select(PsychologistRating.rating)
        .where(
            PsychologistRating.psychologist_id == psychologist.id,
        )
        .order_by(
            PsychologistRating.updated_at.desc(),
            PsychologistRating.id.desc(),
        )
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

    psychologist.average_rating = (
        round(float(average_rating), 2)
        if average_rating is not None
        else None
    )
    psychologist.ratings_count = ratings_count

    db.add(psychologist)
    await db.flush()