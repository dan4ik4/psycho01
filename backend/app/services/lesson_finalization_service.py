from uuid import UUID

from sqlalchemy import select, func, and_
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.call import Call
from app.models.call_event import CallEvent, CallEventType

from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.slot import Slot
from app.models.slot_event import SlotEvent, SlotEventType


async def user_joined_lesson_call(
    db: AsyncSession,
    slot_id: UUID,
    user_id: UUID,
) -> bool:
    stmt = (
        select(CallEvent.id)
        .join(Call, CallEvent.call_id == Call.id)
        .where(
            Call.slot_id == slot_id,
            CallEvent.user_id == user_id,
            CallEvent.event_type == CallEventType.JOINED,
        )
        .limit(1)
    )

    result = await db.execute(stmt)
    return result.scalar_one_or_none() is not None

async def get_latest_slot_event(
    db: AsyncSession,
    slot_id,
) -> SlotEvent | None:
    stmt = (
        select(SlotEvent)
        .where(SlotEvent.slot_id == slot_id)
        .order_by(SlotEvent.created_at.desc())
        .limit(1)
    )

    result = await db.execute(stmt)
    return result.scalar_one_or_none()

async def try_resolve_expired_lesson_outcome(
    db: AsyncSession,
    slot: Slot,
) -> SlotEvent | None:
    now = datetime.now(timezone.utc)

    if slot.end_at > now:
        return None

    latest_event = await get_latest_slot_event(
        db=db,
        slot_id=slot.id,
    )

    if latest_event is None:
        return None

    if latest_event.event_type != SlotEventType.BOOKED:
        return None

    patient_id = latest_event.patient_id
    psychologist_id = slot.psychologist_id

    patient_joined = await user_joined_lesson_call(
        db=db,
        slot_id=slot.id,
        user_id=patient_id,
    )

    psychologist_joined = await user_joined_lesson_call(
        db=db,
        slot_id=slot.id,
        user_id=psychologist_id,
    )

    if patient_joined and psychologist_joined:
        event_type = SlotEventType.COMPLETED
        comment = (
            "Automatically marked as completed: "
            "both participants joined the call"
        )

    elif not patient_joined and psychologist_joined:
        event_type = SlotEventType.MISSED
        comment = (
            "Automatically marked as missed: "
            "patient did not join the call"
        )

    elif patient_joined and not psychologist_joined:
        event_type = SlotEventType.MISSED
        comment = (
            "Automatically marked as missed: "
            "psychologist did not join the call"
        )

    else:
        event_type = SlotEventType.MISSED
        comment = (
            "Automatically marked as missed: "
            "neither participant joined the call"
        )

    final_event = SlotEvent(
        slot_id=slot.id,
        patient_id=patient_id,
        event_type=event_type,
        performed_by_id=None,
        comment=comment,
    )

    db.add(final_event)
    await db.commit()
    await db.refresh(final_event)

    return final_event

async def resolve_expired_lesson_outcomes(
    db: AsyncSession,
    limit: int = 100,
) -> int:
    now = datetime.now(timezone.utc)

    latest_events_subq = (
        select(
            SlotEvent.slot_id.label("slot_id"),
            func.max(SlotEvent.created_at).label("latest_created_at"),
        )
        .group_by(SlotEvent.slot_id)
        .subquery()
    )

    stmt = (
        select(Slot)
        .join(
            latest_events_subq,
            latest_events_subq.c.slot_id == Slot.id,
        )
        .join(
            SlotEvent,
            and_(
                SlotEvent.slot_id == Slot.id,
                SlotEvent.created_at == latest_events_subq.c.latest_created_at,
            ),
        )
        .where(
            Slot.end_at <= now,
            SlotEvent.event_type == SlotEventType.BOOKED,
        )
        .order_by(Slot.end_at.asc())
        .limit(limit)
    )

    result = await db.execute(stmt)
    slots = result.scalars().all()

    finalized_count = 0

    for slot in slots:
        final_event = await try_resolve_expired_lesson_outcome(
            db=db,
            slot=slot,
        )

        if final_event is not None:
            finalized_count += 1

    return finalized_count