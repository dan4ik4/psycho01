import uuid
from datetime import datetime, timezone

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import (
    ConflictError,
    NotFoundError,
)
from app.crud.patient_assignment import (
    get_active_assignments,
    get_active_or_pending_patient_assignment,
    get_incoming_assignment_requests,
)
from app.crud.user import get_user_by_id
from app.models.user import User
from app.crud.slot import get_slots_with_latest_events
from app.models.slot_event import SlotEventType


async def toggle_psychologist(
    db: AsyncSession,
    user_id: uuid.UUID,
) -> User:
    user = await get_user_by_id(
        db=db,
        user_id=user_id,
        for_update=True,
    )

    if user is None:
        raise NotFoundError(
            "User not found"
        )

    if user.is_psychologist:
        active_assignments = await get_active_assignments(
            db=db,
            psychologist_id=user.id,
        )

        pending_assignments = await get_incoming_assignment_requests(
            db=db,
            psychologist_id=user.id,
        )

        if active_assignments or pending_assignments:
            raise ConflictError(
                "Psychologist role cannot be removed while "
                "there are active or pending assignments"
            )
        
        slots_with_events = await get_slots_with_latest_events(
            db=db,
            psychologist_id=user.id,
        )

        now = datetime.now(timezone.utc)

        has_future_slots = any(
            slot.end_at > now
            and (
                latest_event is None
                or latest_event.event_type
                != SlotEventType.REMOVED
            )
            for slot, latest_event in slots_with_events
        )

        if has_future_slots:
            raise ConflictError(
                "Psychologist role cannot be removed while "
                "there are active future slots"
            )
        
    else:
        patient_assignment = (
            await get_active_or_pending_patient_assignment(
                db=db,
                patient_id=user.id,
            )
        )

        if patient_assignment is not None:
            raise ConflictError(
                "Psychologist role cannot be enabled while "
                "the user has an active or pending patient assignment"
            )

    user.is_psychologist = not user.is_psychologist

    await db.commit()
    await db.refresh(user)

    return user