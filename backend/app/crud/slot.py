import uuid
from datetime import datetime, timezone

from sqlalchemy import Select, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.appointment import AvailabilitySlot


async def create_slot(
    session: AsyncSession,
    psychologist_id: uuid.UUID,
    start_at: datetime,
    end_at: datetime,
) -> AvailabilitySlot:
    slot = AvailabilitySlot(
        psychologist_id=psychologist_id,
        start_at=start_at,
        end_at=end_at,
    )
    session.add(slot)
    await session.commit()
    await session.refresh(slot)
    return slot


async def get_psychologist_slots(
    session: AsyncSession,
    psychologist_id: uuid.UUID,
) -> list[AvailabilitySlot]:
    stmt: Select[tuple[AvailabilitySlot]] = (
        select(AvailabilitySlot)
        .where(AvailabilitySlot.psychologist_id == psychologist_id)
        .order_by(AvailabilitySlot.start_at.asc())
    )
    result = await session.execute(stmt)
    return list(result.scalars().all())


async def get_slot_by_id(
    session: AsyncSession,
    slot_id: uuid.UUID,
) -> AvailabilitySlot | None:
    stmt: Select[tuple[AvailabilitySlot]] = select(AvailabilitySlot).where(
        AvailabilitySlot.id == slot_id
    )
    result = await session.execute(stmt)
    return result.scalar_one_or_none()


async def delete_slot(
    session: AsyncSession,
    slot: AvailabilitySlot,
) -> None:
    await session.delete(slot)
    await session.commit()

async def get_available_slots_for_patient(
    session: AsyncSession,
    psychologist_id: uuid.UUID,
) -> list[AvailabilitySlot]:
    now = datetime.now(timezone.utc)

    stmt: Select[tuple[AvailabilitySlot]] = (
        select(AvailabilitySlot)
        .where(AvailabilitySlot.psychologist_id == psychologist_id)
        .where(AvailabilitySlot.is_booked.is_(False))
        .where(AvailabilitySlot.start_at > now)
        .order_by(AvailabilitySlot.start_at.asc())
    )
    result = await session.execute(stmt)
    return list(result.scalars().all())