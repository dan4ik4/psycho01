from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.deps import get_db  # поправь под твой dependency
from app.models.user import User
from app.models.psychologist_profile import PsychologistProfile
from app.schemas.psychologists import PsychologistListItem
from app.models.user import UserRole  # если роли у тебя в enum


router = APIRouter(prefix="/psychologists", tags=["psychologists"])


@router.get("", response_model=list[PsychologistListItem])
async def list_psychologists(db: AsyncSession = Depends(get_db)):

    stmt = (
        select(User, PsychologistProfile)
        .join(PsychologistProfile, PsychologistProfile.user_id == User.id)
        .where(User.role == UserRole.psychologist)
    )

    res = await db.execute(stmt)
    rows = res.all()

    out: list[PsychologistListItem] = []

    for user, profile in rows:
        out.append(
            PsychologistListItem(
                id=user.id,
                email=user.email,
                specialization=profile.specialization,
                experience_years=profile.experience_years,
                licence_number=profile.license_number,
                price_per_hour=profile.price_per_hour,
                bio=profile.bio,
            )
        )

    return out