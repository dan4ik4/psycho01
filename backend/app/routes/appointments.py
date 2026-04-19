from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
import uuid
from datetime import datetime, timezone

from app.auth.deps import current_active_user
from app.crud.slot import get_available_slots_for_patient
from app.db.deps import get_db
from app.models.user import User, UserRole
from app.schemas.appointment import AvailableSlotOut, AppointmentBookIn, AppointmentOut
from app.models.patient_assignment import PatientAssignment, AssignmentStatus
from app.crud.appointment import book_slot, get_slot_for_booking, cancel_appointment, get_appointment_by_id
from app.crud.appointment import get_user_appointments_history, get_user_appointments
router = APIRouter(prefix="/appointments", tags=["appointments"])


async def get_attached_psychologist_id(
    session: AsyncSession,
    current_user: User,
):
    stmt = (
        select(PatientAssignment.psychologist_id)
        .where(PatientAssignment.patient_id == current_user.id)
        .where(PatientAssignment.status == AssignmentStatus.ACTIVE)
    )

    result = await session.execute(stmt)
    psychologist_id = result.scalar_one_or_none()

    if psychologist_id is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No active psychologist assigned.",
        )

    return psychologist_id


@router.get("/available-slots", response_model=list[AvailableSlotOut])
async def get_my_available_slots(
    session: AsyncSession = Depends(get_db),
    current_user: User = Depends(current_active_user),
) -> list[AvailableSlotOut]:
    if current_user.role != UserRole.user:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only patients can view available slots.",
        )

    psychologist_id = await get_attached_psychologist_id(
        session=session,
        current_user=current_user,
    )

    slots = await get_available_slots_for_patient(
        session=session,
        psychologist_id=psychologist_id,
    )
    return slots

@router.post("/book", response_model=AppointmentOut, status_code=status.HTTP_201_CREATED)
async def book_appointment(
    data: AppointmentBookIn,
    session: AsyncSession = Depends(get_db),
    current_user: User = Depends(current_active_user),
) -> AppointmentOut:
    if current_user.role != UserRole.user:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only patients can book slots.",
        )

    psychologist_id = await get_attached_psychologist_id(
        session=session,
        current_user=current_user,
    )

    slot = await get_slot_for_booking(
        session=session,
        slot_id=data.slot_id,
    )
    if slot is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Slot not found.",
        )

    if slot.psychologist_id != psychologist_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You can book only slots of your assigned psychologist.",
        )

    if slot.is_booked:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Slot is already booked.",
        )

    now = datetime.now(timezone.utc)
    if slot.start_at <= now:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot book a slot that has already started or passed.",
        )

    appointment = await book_slot(
        session=session,
        slot=slot,
        patient_id=current_user.id,
    )
    return appointment

@router.get("/my", response_model=list[AppointmentOut])
async def get_my_appointments(
    session: AsyncSession = Depends(get_db),
    current_user: User = Depends(current_active_user),
):

    appointments = await get_user_appointments(session, current_user)

    result = []
    for appt in appointments:
        result.append(
            AppointmentOut(
                id=appt.id,
                slot_id=appt.slot_id,
                psychologist_id=appt.psychologist_id,
                patient_id=appt.patient_id,
                status=appt.status,
                missed_by=appt.missed_by,
                start_at=appt.slot.start_at,
                end_at=appt.slot.end_at,
            )
        )

    return result

@router.delete("/{appointment_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_appointment(
    appointment_id: uuid.UUID,
    session: AsyncSession = Depends(get_db),
    current_user: User = Depends(current_active_user),
):
    appointment = await get_appointment_by_id(
        session=session,
        appointment_id=appointment_id,
    )

    if appointment is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Appointment not found.",
        )

    if appointment.patient_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You can cancel only your own appointments.",
        )

    await cancel_appointment(
        session=session,
        appointment=appointment,
    )


@router.get("/history", response_model=list[AppointmentOut])
async def get_my_appointments_history(
    user: User = Depends(current_active_user),
    session: AsyncSession = Depends(get_db),
):
    appointments = await get_user_appointments_history(session, user)

    result = []
    for appt in appointments:
        result.append(
            AppointmentOut(
                id=appt.id,
                slot_id=appt.slot_id,
                psychologist_id=appt.psychologist_id,
                patient_id=appt.patient_id,
                status=appt.status,
                missed_by=appt.missed_by,
                start_at=appt.slot.start_at,
                end_at=appt.slot.end_at,
            )
        )

    return result