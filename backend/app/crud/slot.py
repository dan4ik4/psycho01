import uuid

from sqlalchemy import select, func, and_
from sqlalchemy.ext.asyncio import AsyncSession

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
    for_update: bool = False,
) -> Slot | None:
    query = select(Slot).where(Slot.id == slot_id)

    if for_update:
        query = query.with_for_update()

    result = await db.execute(query)

    return result.scalar_one_or_none()

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
        .order_by(
            SlotEvent.created_at.desc(),
            SlotEvent.id.desc(),
            )
        .limit(1)
    )

    return result.scalar_one_or_none()

async def get_slots_with_latest_events(
    db: AsyncSession,
    psychologist_id: uuid.UUID | None = None,
) -> list[tuple[Slot, SlotEvent | None]]:
    ranked_events_subquery = (
        select(
            SlotEvent.id.label("event_id"),
            SlotEvent.slot_id.label("slot_id"),
            func.row_number()
            .over(
                partition_by=SlotEvent.slot_id,
                order_by=(
                    SlotEvent.created_at.desc(),
                    SlotEvent.id.desc(),
                ),
            )
            .label("event_position"),
        )
        .subquery()
    )

    query = (
        select(Slot, SlotEvent)
        .outerjoin(
            ranked_events_subquery,
            and_(
                Slot.id == ranked_events_subquery.c.slot_id,
                ranked_events_subquery.c.event_position == 1,
            ),
        )
        .outerjoin(
            SlotEvent,
            SlotEvent.id == ranked_events_subquery.c.event_id,
        )
        .order_by(Slot.start_at.asc())
    )

    if psychologist_id is not None:
        query = query.where(
            Slot.psychologist_id == psychologist_id,
        )

    result = await db.execute(query)

    return list(result.all())

async def get_slot_history_events(
    db: AsyncSession,
    user_id: uuid.UUID,
    is_psychologist: bool,
) -> list[tuple[Slot, SlotEvent]]:
    history_events = (
        SlotEventType.CANCELLED,
        SlotEventType.COMPLETED,
        SlotEventType.MISSED,
        SlotEventType.REMOVED,
    )

    query = (
        select(Slot, SlotEvent)
        .join(
            SlotEvent,
            SlotEvent.slot_id == Slot.id,
        )
        .where(
            SlotEvent.event_type.in_(history_events),
        )
        .order_by(SlotEvent.created_at.desc())
    )

    if is_psychologist:
        query = query.where(
            Slot.psychologist_id == user_id,
        )
    else:
        query = query.where(
            SlotEvent.patient_id == user_id,
        )

    result = await db.execute(query)

    return list(result.all())

