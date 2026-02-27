from __future__ import annotations

import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.deps import get_db
from app.models.user import User, UserRole
from app.models.patient_assignment import PatientAssignment, AssignmentStatus
from app.auth.deps import current_active_user  # если у тебя иначе — поправим


router = APIRouter(prefix="/patients/me", tags=["patient-assignment"])


class AssignPsychologistIn(BaseModel):
    psychologist_id: uuid.UUID

class MyAssignmentOut(BaseModel):
    psychologist_id: uuid.UUID
    psychologist_email: str | None = None


@router.post("/assignment", status_code=status.HTTP_201_CREATED)
async def assign_psychologist(
    payload: AssignPsychologistIn,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(current_active_user),
):

    # 1️⃣ пациент не должен быть психологом
    if current_user.role != UserRole.user:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only patients can assign psychologist",
        )

    # 2️⃣ проверяем, есть ли уже активная привязка
    stmt = select(PatientAssignment).where(
        PatientAssignment.patient_id == current_user.id,
        PatientAssignment.status == AssignmentStatus.ACTIVE,
    )
    res = await db.execute(stmt)
    existing = res.scalar_one_or_none()

    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Patient already has active psychologist",
        )

    # 3️⃣ проверяем, что выбранный user — психолог
    stmt = select(User).where(User.id == payload.psychologist_id)
    res = await db.execute(stmt)
    psychologist = res.scalar_one_or_none()

    if not psychologist or psychologist.role != UserRole.psychologist:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid psychologist",
        )

    # 4️⃣ создаём привязку
    assignment = PatientAssignment(
        patient_id=current_user.id,
        psychologist_id=payload.psychologist_id,
        status=AssignmentStatus.ACTIVE,
    )

    db.add(assignment)
    await db.commit()

    return {"ok": True}

@router.get("/assignment", response_model=MyAssignmentOut | None)
async def get_my_assignment(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(current_active_user),
):
    stmt = (
        select(PatientAssignment, User)
        .join(User, User.id == PatientAssignment.psychologist_id)
        .where(
            PatientAssignment.patient_id == current_user.id,
            PatientAssignment.status == AssignmentStatus.ACTIVE,
        )
    )
    res = await db.execute(stmt)
    row = res.first()

    if not row:
        return None

    assignment, psychologist = row

    return MyAssignmentOut(
        psychologist_id=assignment.psychologist_id,
        psychologist_email=psychologist.email,
    )

@router.delete("/assignment", status_code=status.HTTP_204_NO_CONTENT)
async def delete_my_assignment(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(current_active_user),
):
    stmt = select(PatientAssignment).where(
        PatientAssignment.patient_id == current_user.id,
        PatientAssignment.status == AssignmentStatus.ACTIVE,
    )
    res = await db.execute(stmt)
    assignment = res.scalar_one_or_none()

    if not assignment:
        # если нет активной привязки — просто ок (идемпотентность)
        return None

    assignment.status = AssignmentStatus.ENDED
    assignment.ended_at = datetime.now(timezone.utc)

    await db.commit()
    return None