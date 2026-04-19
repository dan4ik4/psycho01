import uuid

from sqlalchemy import Select, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
from datetime import datetime, UTC
from app.models.user import UserRole

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


async def get_user_appointments_history(session: AsyncSession, user) -> list[Appointment]:
    now = datetime.now(UTC)

    stmt = (
        select(Appointment)
        .options(selectinload(Appointment.slot))
        .join(AvailabilitySlot, Appointment.slot_id == AvailabilitySlot.id)
        .where(AvailabilitySlot.end_at < now)
    )

    if user.role == UserRole.user:
        stmt = stmt.where(Appointment.patient_id == user.id)
    elif user.role == UserRole.psychologist:
        stmt = stmt.where(Appointment.psychologist_id == user.id)
    else:
        return []

    stmt = stmt.order_by(AvailabilitySlot.start_at.desc())

    result = await session.execute(stmt)
    return list(result.scalars().all())


async def get_user_appointments(session: AsyncSession, user) -> list[Appointment]:
    now = datetime.now(UTC)

    stmt = (
        select(Appointment)
        .options(selectinload(Appointment.slot))
        .join(AvailabilitySlot, Appointment.slot_id == AvailabilitySlot.id)
        .where(AvailabilitySlot.start_at > now)
    )

    if user.role == UserRole.user:
        stmt = stmt.where(Appointment.patient_id == user.id)
    elif user.role == UserRole.psychologist:
        stmt = stmt.where(Appointment.psychologist_id == user.id)
    else:
        return []

    stmt = stmt.order_by(AvailabilitySlot.start_at.desc())

    result = await session.execute(stmt)
    return list(result.scalars().all())