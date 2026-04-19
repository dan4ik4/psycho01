from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from datetime import datetime, timezone, timedelta
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.core.constants import AGORA_JOIN_WINDOW_MINUTES
from app.schemas.agora import AgoraTokenResponse
from app.db.deps import get_db
from app.models.appointment import Appointment, AppointmentStatus
from app.auth.deps import current_active_user
from app.services.agora import (
    generate_agora_channel_name,
    generate_agora_token,
    generate_agora_uid,
    datetime_to_timestamp,
)

router = APIRouter(prefix="/appointments", tags=["appointments"])

async def get_accessible_appointment_with_slot(
    appointment_id: str,
    db: AsyncSession,
    user,
) -> Appointment:
    result = await db.execute(
        select(Appointment)
        .options(selectinload(Appointment.slot))
        .where(Appointment.id == appointment_id)
    )

    appointment = result.scalar_one_or_none()

    if not appointment:
        raise HTTPException(status_code=404, detail="Appointment not found")

    if appointment.status == AppointmentStatus.cancelled:
        raise HTTPException(status_code=403, detail="Appointment is cancelled")

    if user.id not in [appointment.patient_id, appointment.psychologist_id]:
        raise HTTPException(status_code=403, detail="Access denied")

    return appointment


def ensure_appointment_call_window_open(appointment: Appointment) -> None:
    now = datetime.now(timezone.utc)

    start_time = appointment.slot.start_at
    end_time = appointment.slot.end_at

    allowed_start = start_time - timedelta(minutes=AGORA_JOIN_WINDOW_MINUTES)
    allowed_end = end_time + timedelta(minutes=AGORA_JOIN_WINDOW_MINUTES)

    if now < allowed_start:
        raise HTTPException(status_code=403, detail="Too early to join")

    if now > allowed_end:
        raise HTTPException(status_code=403, detail="Appointment already finished")


@router.post("/{appointment_id}/agora-token", response_model=AgoraTokenResponse)
async def get_agora_token(
    appointment_id: str,
    db: AsyncSession = Depends(get_db),
    user=Depends(current_active_user),
):
    appointment = await get_accessible_appointment_with_slot(
    appointment_id=appointment_id,
    db=db,
    user=user,
)
    ensure_appointment_call_window_open(appointment)

    allowed_end = appointment.slot.end_at + timedelta(minutes=AGORA_JOIN_WINDOW_MINUTES)

    channel_name = generate_agora_channel_name(str(appointment.id))
    expire_timestamp = datetime_to_timestamp(allowed_end)
    uid = generate_agora_uid(user.id)
    token = generate_agora_token(
        channel_name=channel_name,
        uid=uid,
        expire_timestamp=expire_timestamp,
    )

    return {
        "channel_name": channel_name,
        "token": token,
        "uid": uid,
    }

@router.post("/{appointment_id}/join")
async def join_appointment_call(
    appointment_id: str,
    db: AsyncSession = Depends(get_db),
    user=Depends(current_active_user),
):
    appointment = await get_accessible_appointment_with_slot(
        appointment_id=appointment_id,
        db=db,
        user=user,
    )

    ensure_appointment_call_window_open(appointment)

    now = datetime.now(timezone.utc)

    if user.id == appointment.patient_id:
        if appointment.patient_joined_at is not None:
            raise HTTPException(status_code=400, detail="Patient already joined")
        appointment.patient_joined_at = now

    elif user.id == appointment.psychologist_id:
        if appointment.psychologist_joined_at is not None:
            raise HTTPException(status_code=400, detail="Psychologist already joined")
        appointment.psychologist_joined_at = now

    else:
        raise HTTPException(status_code=403, detail="Access denied")

    await db.commit()

    return {"detail": "Join time recorded"}

@router.post("/{appointment_id}/leave")
async def leave_appointment_call(
    appointment_id: str,
    db: AsyncSession = Depends(get_db),
    user=Depends(current_active_user),
):
    appointment = await get_accessible_appointment_with_slot(
        appointment_id=appointment_id,
        db=db,
        user=user,
    )

    ensure_appointment_call_window_open(appointment)

    now = datetime.now(timezone.utc)

    if user.id == appointment.patient_id:
        if appointment.patient_joined_at is None:
            raise HTTPException(status_code=400, detail="Patient has not joined yet")
        if appointment.patient_left_at is not None:
            raise HTTPException(status_code=400, detail="Patient already left")
        appointment.patient_left_at = now

    elif user.id == appointment.psychologist_id:
        if appointment.psychologist_joined_at is None:
            raise HTTPException(status_code=400, detail="Psychologist has not joined yet")
        if appointment.psychologist_left_at is not None:
            raise HTTPException(status_code=400, detail="Psychologist already left")
        appointment.psychologist_left_at = now

    else:
        raise HTTPException(status_code=403, detail="Access denied")

    await db.commit()

    return {"detail": "Leave time recorded"}