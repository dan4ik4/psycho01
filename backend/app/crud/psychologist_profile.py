from __future__ import annotations

from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.psychologist_profile import PsychologistProfile
from app.schemas.psychologist_profile import PsychologistProfileUpdate


async def get_by_user_id(db: AsyncSession, user_id: UUID) -> PsychologistProfile | None:
    res = await db.execute(
        select(PsychologistProfile).where(PsychologistProfile.user_id == user_id)
    )
    return res.scalar_one_or_none()


async def create_for_user(db: AsyncSession, user_id: UUID) -> PsychologistProfile:
    profile = PsychologistProfile(user_id=user_id)
    db.add(profile)
    try:
        await db.commit()
    except IntegrityError:
        # race: кто-то уже создал параллельно
        await db.rollback()
        existing = await get_by_user_id(db, user_id)
        if existing:
            return existing
        raise
    await db.refresh(profile)
    return profile


async def ensure_for_user(db: AsyncSession, user_id: UUID) -> PsychologistProfile:
    prof = await get_by_user_id(db, user_id)
    return prof if prof else await create_for_user(db, user_id)


async def update_for_user(
    db: AsyncSession, user_id: UUID, data: PsychologistProfileUpdate
) -> PsychologistProfile:
    try:
        prof = await ensure_for_user(db, user_id)

        for field, value in data.model_dump(exclude_unset=True).items():
            setattr(prof, field, value)

        db.add(prof)
        await db.commit()
        await db.refresh(prof)
        return prof
    except Exception as e:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"psychologist_profile_update_error: {e}",
        )