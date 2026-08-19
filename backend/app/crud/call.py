import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from datetime import datetime

from app.models.call import Call, CallProvider
from app.models.call_event import CallEvent, CallEventType


async def get_call_by_slot_id(
    db: AsyncSession,
    slot_id: uuid.UUID,
) -> Call | None:
    result = await db.execute(
        select(Call).where(Call.slot_id == slot_id)
    )
    return result.scalar_one_or_none()


async def create_call(
    db: AsyncSession,
    slot_id: uuid.UUID,
    provider: CallProvider = CallProvider.AGORA,
) -> Call:
    call = Call(
        slot_id=slot_id,
        provider=provider,
    )

    db.add(call)
    await db.flush()
    return call


async def create_call_event(
    db: AsyncSession,
    call_id: uuid.UUID,
    user_id: uuid.UUID | None,
    event_type: CallEventType,
) -> CallEvent:
    event = CallEvent(
        call_id=call_id,
        user_id=user_id,
        event_type=event_type,
    )

    db.add(event)
    await db.flush()
    return event


async def get_latest_call_event_for_user(
    db: AsyncSession,
    call_id: uuid.UUID,
    user_id: uuid.UUID,
    booking_started_at: datetime,
) -> CallEvent | None:
    result = await db.execute(
        select(CallEvent)
        .where(
            CallEvent.call_id == call_id,
            CallEvent.user_id == user_id,
            CallEvent.created_at >= booking_started_at,
        )
        .order_by(
            CallEvent.created_at.desc(),
            CallEvent.id.desc(),
        )
        .limit(1)
    )

    return result.scalar_one_or_none()


async def get_call_events(
    db: AsyncSession,
    call_id: uuid.UUID,
) -> list[CallEvent]:
    result = await db.execute(
        select(CallEvent)
        .where(CallEvent.call_id == call_id)
        .order_by(CallEvent.id)
    )
    return list(result.scalars().all())

async def has_joined_call_event_for_slot(
    db: AsyncSession,
    slot_id: uuid.UUID,
) -> bool:
    joined_event_exists = (
        select(CallEvent.id)
        .join(
            Call,
            Call.id == CallEvent.call_id,
        )
        .where(
            Call.slot_id == slot_id,
            CallEvent.event_type == CallEventType.JOINED,
        )
        .exists()
    )

    result = await db.execute(
        select(joined_event_exists)
    )

    return bool(result.scalar_one())