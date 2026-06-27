import uuid

from sqlalchemy import select, func, and_
from sqlalchemy.ext.asyncio import AsyncSession
from datetime import datetime

from app.models.slot import Slot
from app.models.slot_event import SlotEvent, SlotEventType


async def create_slot(
    db: AsyncSession,
    psychologist_id: uuid.UUID,
    start_at,
    end_at,
) -> Slot:
    slot = Slot(
        psychologist_id=psychologist_id,
        start_at=start_at,
        end_at=end_at,
    )

    db.add(slot)
    await db.flush()

    return slot


async def get_slot_by_id(
    db: AsyncSession,
    slot_id: uuid.UUID,
) -> Slot | None:
    result = await db.execute(
        select(Slot).where(Slot.id == slot_id)
    )

    return result.scalar_one_or_none()


async def get_slots_by_psychologist(
    db: AsyncSession,
    psychologist_id: uuid.UUID,
) -> list[Slot]:
    result = await db.execute(
        select(Slot)
        .where(Slot.psychologist_id == psychologist_id)
        .order_by(Slot.start_at.asc())
    )

    return list(result.scalars().all())


async def create_slot_event(
    db: AsyncSession,
    slot_id: uuid.UUID,
    event_type: SlotEventType,
    performed_by_id: uuid.UUID | None = None,
    patient_id: uuid.UUID | None = None,
    comment: str | None = None,
) -> SlotEvent:
    event = SlotEvent(
        slot_id=slot_id,
        event_type=event_type,
        performed_by_id=performed_by_id,
        patient_id=patient_id,
        comment=comment,
    )

    db.add(event)
    await db.flush()

    return event


async def get_latest_slot_event(
    db: AsyncSession,
    slot_id: uuid.UUID,
) -> SlotEvent | None:
    result = await db.execute(
        select(SlotEvent)
        .where(SlotEvent.slot_id == slot_id)
        .order_by(SlotEvent.created_at.desc())
        .limit(1)
    )

    return result.scalar_one_or_none()

async def get_slots_with_latest_events(
    db: AsyncSession,
    psychologist_id: uuid.UUID | None = None,
) -> list[tuple[Slot, SlotEvent | None]]:
    latest_events_subquery = (
        select(
            SlotEvent.slot_id,
            func.max(SlotEvent.created_at).label("latest_created_at"),
        )
        .group_by(SlotEvent.slot_id)
        .subquery()
    )

    query = (
        select(Slot, SlotEvent)
        .outerjoin(
            latest_events_subquery,
            Slot.id == latest_events_subquery.c.slot_id,
        )
        .outerjoin(
            SlotEvent,
            and_(
                SlotEvent.slot_id == latest_events_subquery.c.slot_id,
                SlotEvent.created_at == latest_events_subquery.c.latest_created_at,
            ),
        )
        .order_by(Slot.start_at.asc())
    )

    if psychologist_id is not None:
        query = query.where(Slot.psychologist_id == psychologist_id)

    result = await db.execute(query)

    return list(result.all())

