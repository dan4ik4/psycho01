import uuid

from sqlalchemy import Select, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.appointment import Appointment, AppointmentStatus, AvailabilitySlot


async def book_slot(
    session: AsyncSession,
    slot: AvailabilitySlot,
    patient_id: uuid.UUID,
) -> Appointment:
    appointment = Appointment(
        slot_id=slot.id,
        psychologist_id=slot.psychologist_id,
        patient_id=patient_id,
        status=AppointmentStatus.scheduled,
    )

    slot.is_booked = True

    session.add(appointment)
    await session.commit()
    await session.refresh(appointment)
    return appointment


async def get_slot_for_booking(
    session: AsyncSession,
    slot_id: uuid.UUID,
) -> AvailabilitySlot | None:
    stmt: Select[tuple[AvailabilitySlot]] = select(AvailabilitySlot).where(
        AvailabilitySlot.id == slot_id
    )
    result = await session.execute(stmt)
    return result.scalar_one_or_none()

async def get_patient_appointments(
    session: AsyncSession,
    patient_id: uuid.UUID,
) -> list[Appointment]:
    stmt: Select[tuple[Appointment]] = (
        select(Appointment)
        .options(selectinload(Appointment.slot))
        .where(Appointment.patient_id == patient_id)
        .order_by(Appointment.created_at.desc())
    )

    result = await session.execute(stmt)
    return list(result.scalars().all())

async def cancel_appointment(
    session: AsyncSession,
    appointment: Appointment,
) -> None:
    if appointment.slot:
        appointment.slot.is_booked = False

    await session.delete(appointment)
    await session.commit()

async def get_appointment_by_id(
    session: AsyncSession,
    appointment_id: uuid.UUID,
) -> Appointment | None:
    stmt: Select[tuple[Appointment]] = (
        select(Appointment)
        .options(selectinload(Appointment.slot))
        .where(Appointment.id == appointment_id)
    )

    result = await session.execute(stmt)
    return result.scalar_one_or_none()

async def get_psychologist_appointments(
    session: AsyncSession,
    psychologist_id: uuid.UUID,
) -> list[Appointment]:
    stmt: Select[tuple[Appointment]] = (
        select(Appointment)
        .options(selectinload(Appointment.slot))
        .where(Appointment.psychologist_id == psychologist_id)
        .order_by(Appointment.created_at.desc())
    )

    result = await session.execute(stmt)
    return list(result.scalars().all())