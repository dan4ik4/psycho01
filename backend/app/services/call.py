import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.exc import IntegrityError

from app.core.settings import settings
from app.crud.call import (
    create_call,
    create_call_event,
    get_call_by_slot_id,
)
from app.crud.slot import get_slot_by_id
from app.models.call_event import CallEventType
from app.schemas.call import CallJoinOut
from app.services.agora import (
    generate_agora_channel_name,
    generate_agora_token,
    generate_agora_uid,
)

from app.crud.slot import get_latest_slot_event
from app.models.slot_event import SlotEventType


async def join_call(
    db: AsyncSession,
    slot_id: uuid.UUID,
    user,
) -> CallJoinOut:
    slot = await get_slot_by_id(
        db=db,
        slot_id=slot_id,
    )

    if slot is None:
        raise ValueError("Slot not found")
    
    latest_slot_event = await get_latest_slot_event(
        db=db,
        slot_id=slot.id,
    )

    if user.id == slot.psychologist_id:
        pass
    elif (
        latest_slot_event is not None
        and latest_slot_event.event_type == SlotEventType.BOOKED
        and latest_slot_event.patient_id == user.id
    ):
        pass
    else:
        raise ValueError("You are not allowed to join this call")

    now = datetime.now(timezone.utc)

    join_from = slot.start_at - timedelta(
        minutes=settings.AGORA_JOIN_WINDOW_MINUTES,
    )

    if now < join_from:
        raise ValueError("Call is not available yet")

    call = await get_call_by_slot_id(
        db=db,
        slot_id=slot.id,
    )

    if call is None:
        try:
            call = await create_call(
                db=db,
                slot_id=slot.id,
            )
            await db.flush()
        except IntegrityError:
            await db.rollback()

            call = await get_call_by_slot_id(
                db=db,
                slot_id=slot.id,
            )

            if call is None:
                raise ValueError("Call creation failed")

    await create_call_event(
        db=db,
        call_id=call.id,
        user_id=user.id,
        event_type=CallEventType.JOINED,
    )

    room_id = generate_agora_channel_name(
        call_id=str(call.id),
    )

    uid = generate_agora_uid(user.id)

    expire_at = slot.end_at + timedelta(
        settings.AGORA_JOIN_WINDOW_MINUTES,
    )

    token = generate_agora_token(
        channel_name=room_id,
        uid=uid,
        expire_timestamp=int(expire_at.timestamp()),
    )

    await db.commit()

    return CallJoinOut(
        call_id=call.id,
        slot_id=slot.id,
        provider=call.provider,
        room_id=room_id,
        token=token,
        app_id=settings.AGORA_APP_ID,
    )

async def leave_call(
    db: AsyncSession,
    slot_id: uuid.UUID,
    user,
) -> None:
    slot = await get_slot_by_id(
        db=db,
        slot_id=slot_id,
    )

    if slot is None:
        raise ValueError("Slot not found")

    latest_slot_event = await get_latest_slot_event(
        db=db,
        slot_id=slot.id,
    )

    if user.id == slot.psychologist_id:
        pass
    elif (
        latest_slot_event is not None
        and latest_slot_event.event_type == SlotEventType.BOOKED
        and latest_slot_event.patient_id == user.id
    ):
        pass
    else:
        raise ValueError("You are not allowed to leave this call")

    call = await get_call_by_slot_id(
        db=db,
        slot_id=slot.id,
    )

    if call is None:
        raise ValueError("Call not found")

    await create_call_event(
        db=db,
        call_id=call.id,
        user_id=user.id,
        event_type=CallEventType.LEFT,
    )

    await db.commit()