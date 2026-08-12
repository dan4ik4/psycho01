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
from app.core.errors import (
    ConflictError,
    ForbiddenError,
    InternalError,
    NotFoundError,
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
        for_update=True,
    )

    if slot is None:
        raise NotFoundError("Slot not found")
    
    if (
        user.id == slot.psychologist_id
        and not user.is_psychologist
    ):
        raise ForbiddenError(
            "Psychologist role is no longer active"
        )
    
    latest_slot_event = await get_latest_slot_event(
        db=db,
        slot_id=slot.id,
    )

    if (
        latest_slot_event is None
        or latest_slot_event.event_type != SlotEventType.BOOKED
    ):
        raise ConflictError("Slot is not booked")

    if (
        user.id != slot.psychologist_id
        and user.id != latest_slot_event.patient_id
    ):
        raise ForbiddenError("You are not allowed to join this call")

    now = datetime.now(timezone.utc)

    join_from = slot.start_at - timedelta(
        minutes=settings.AGORA_JOIN_WINDOW_MINUTES,
    )

    join_until = slot.end_at + timedelta(
        minutes=settings.AGORA_JOIN_WINDOW_MINUTES,
    )

    if now < join_from:
        raise ConflictError("Call is not available yet")
    
    if now > join_until:
        raise ConflictError("Call is no longer available")

    call = await get_call_by_slot_id(
        db=db,
        slot_id=slot.id,
    )

    if call is None:
        try:
            async with db.begin_nested():
                call = await create_call(
                    db=db,
                    slot_id=slot.id,
                )
                await db.flush()
        except IntegrityError:
            call = await get_call_by_slot_id(
                db=db,
                slot_id=slot.id,
            )

            if call is None:
                raise InternalError("Call creation failed")

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
        minutes=settings.AGORA_JOIN_WINDOW_MINUTES,
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
        raise NotFoundError("Slot not found")

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
        raise ForbiddenError("You are not allowed to leave this call")

    call = await get_call_by_slot_id(
        db=db,
        slot_id=slot.id,
    )

    if call is None:
        raise NotFoundError("Call not found")

    await create_call_event(
        db=db,
        call_id=call.id,
        user_id=user.id,
        event_type=CallEventType.LEFT,
    )

    await db.commit()

