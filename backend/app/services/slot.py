from datetime import datetime, timezone, timedelta
import uuid

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import delete, exists, select

from app.crud.slot import (
    create_slot as create_slot_crud,
    create_slot_event,
    get_latest_slot_event,
    get_slot_by_id,
    get_slots_with_latest_events,
    get_slot_history_events,
)
from app.crud.patient_assignment import (
    get_latest_patient_assignment,
    get_assignment_by_id,
    get_latest_assignment_event,
)
from app.core.errors import (
    ConflictError,
    ForbiddenError,
    NotFoundError,
    ValidationError,
)
from app.crud.user import get_user_by_id
from app.models.slot import Slot
from app.models.slot_event import SlotEventType, SlotEvent
from app.models.user import User
from app.models.patient_assignment_event import PatientAssignmentEventType
from app.crud.call import has_joined_call_event_for_slot

#psychologist
async def create_slot(
    db: AsyncSession,
    user: User,
    start_at: datetime,
    end_at: datetime,
) -> Slot:
    locked_user = await get_user_by_id(
        db=db,
        user_id=user.id,
        for_update=True,
    )

    if (
        locked_user is None
        or not locked_user.is_active
        or not locked_user.is_psychologist
    ):
        raise ForbiddenError(
            "Only active psychologists can create slots"
        )
    
    now = datetime.now(timezone.utc)

    if start_at <= now:
        raise ValidationError("Slot start time must be in the future")

    if end_at <= now:
        raise ValidationError("Slot end time must be in the future")

    if start_at >= end_at:
        raise ValidationError("Slot start time must be before end time")

    if end_at - start_at < timedelta(minutes=15):
        raise ValidationError("Slot duration must be at least 15 minutes")

    slots_with_events = await get_slots_with_latest_events(
        db=db,
        psychologist_id=locked_user.id,
    )

    for slot, latest_event in slots_with_events:
        if (
            latest_event is not None
            and latest_event.event_type != SlotEventType.REMOVED
            and start_at < slot.end_at
            and end_at > slot.start_at
        ):
            raise ConflictError("Slot overlaps with existing slot")

    slot = await create_slot_crud(
        db=db,
        psychologist_id=locked_user.id,
        start_at=start_at,
        end_at=end_at,
    )

    await create_slot_event(
        db=db,
        slot_id=slot.id,
        event_type=SlotEventType.CREATED,
        performed_by_id=locked_user.id,
    )

    await db.commit()
    await db.refresh(slot)

    return slot

async def get_my_slots(
    db: AsyncSession,
    user: User,
) -> list[Slot]:
    if not user.is_psychologist:
        raise ForbiddenError("Only psychologists can view their slots")

    slots_with_events = await get_slots_with_latest_events(
        db=db,
        psychologist_id=user.id,
    )

    now = datetime.now(timezone.utc)

    return [
        slot
        for slot, latest_event in slots_with_events
        if (
            slot.end_at > now
            and latest_event is not None
            and latest_event.event_type != SlotEventType.REMOVED
        )
    ]

async def remove_slot(
    db: AsyncSession,
    slot_id: uuid.UUID,
    user: User,
    comment: str | None = None,
) -> Slot:
    if not user.is_psychologist:
        raise ForbiddenError("Only psychologists can remove slots")

    slot = await get_slot_by_id(
        db=db,
        slot_id=slot_id,
        for_update=True,
    )

    if slot is None:
        raise NotFoundError("Slot not found")

    if slot.psychologist_id != user.id:
        raise ForbiddenError("You are not allowed to remove this slot")

    latest_event = await get_latest_slot_event(
        db=db,
        slot_id=slot_id,
    )

    if latest_event is None:
        raise ConflictError("Slot has no events")

    if latest_event.event_type == SlotEventType.REMOVED:
        raise ConflictError("Slot is already removed")

    if latest_event.event_type not in (
        SlotEventType.CREATED,
        SlotEventType.CANCELLED,
    ):
        raise ConflictError(
            "Only available slot can be removed"
        )

    await create_slot_event(
        db=db,
        slot_id=slot.id,
        event_type=SlotEventType.REMOVED,
        performed_by_id=user.id,
        comment=comment,
    )

    await db.commit()
    await db.refresh(slot)

    return slot

#patient
async def get_available_slots(
    db: AsyncSession,
    user: User,
) -> list[Slot]:
    if user.is_psychologist:
        raise ForbiddenError("Only patients can view available slots")

    assignment_data = await get_latest_patient_assignment(
        db=db,
        patient_id=user.id,
    )

    if assignment_data is None:
        raise ConflictError("Patient has no assignment")

    assignment, latest_assignment_event = assignment_data

    if latest_assignment_event.event_type != PatientAssignmentEventType.ACCEPTED:
        raise ConflictError("Patient has no active assignment")

    slots_with_events = await get_slots_with_latest_events(
        db=db,
        psychologist_id=assignment.psychologist_id,
    )

    now = datetime.now(timezone.utc)

    return [
        slot
        for slot, latest_event in slots_with_events
        if (
            slot.start_at > now
            and latest_event is not None
            and latest_event.event_type in (
                SlotEventType.CREATED,
                SlotEventType.CANCELLED,
            )
        )
    ]

async def book_slot(
    db: AsyncSession,
    slot_id: uuid.UUID,
    user: User,
) -> Slot:
    if user.is_psychologist:
        raise ForbiddenError("Only patients can book slots")

    assignment_data = await get_latest_patient_assignment(
        db=db,
        patient_id=user.id,
    )

    if assignment_data is None:
        raise ConflictError("Patient has no assignment")

    assignment, _ = assignment_data

    assignment = await get_assignment_by_id(
        db=db,
        assignment_id=assignment.id,
        for_update=True,
    )

    if assignment is None:
        raise ConflictError("Patient has no assignment")

    latest_assignment_event = await get_latest_assignment_event(
        db=db,
        assignment_id=assignment.id,
    )

    if (
        latest_assignment_event is None
        or latest_assignment_event.event_type
        != PatientAssignmentEventType.ACCEPTED
    ):
        raise ConflictError("Patient has no active assignment")
    
    slot = await get_slot_by_id(
        db=db,
        slot_id=slot_id,
        for_update=True
    )

    if slot is None:
        raise NotFoundError("Slot not found")

    if slot.start_at <= datetime.now(timezone.utc):
        raise ConflictError("Cannot book slot in the past")

    if slot.psychologist_id != assignment.psychologist_id:
        raise ConflictError("Slot does not belong to patient's psychologist")

    latest_slot_event = await get_latest_slot_event(
        db=db,
        slot_id=slot_id,
    )

    if (
        latest_slot_event is None
        or latest_slot_event.event_type not in (
            SlotEventType.CREATED,
            SlotEventType.CANCELLED,
        )
    ):
        raise ConflictError("Slot is not available")

    await create_slot_event(
        db=db,
        slot_id=slot_id,
        event_type=SlotEventType.BOOKED,
        patient_id=user.id,
        performed_by_id=user.id,
    )

    await db.commit()
    await db.refresh(slot)

    return slot

async def cancel_slot_booking(
    db: AsyncSession,
    slot_id: uuid.UUID,
    user: User,
    comment: str | None = None,
) -> Slot:
    slot = await get_slot_by_id(
        db=db,
        slot_id=slot_id,
        for_update=True,
    )

    if slot is None:
        raise NotFoundError("Slot not found")
    
    if slot.start_at <= datetime.now(timezone.utc):
        raise ConflictError("Cannot cancel booking after lesson has started")

    latest_event = await get_latest_slot_event(
        db=db,
        slot_id=slot_id,
    )

    if latest_event is None or latest_event.event_type != SlotEventType.BOOKED:
        raise ConflictError("Slot is not booked")
    
    normalized_comment = (
        comment.strip()
        if comment is not None
        else None
    )

    if normalized_comment == "":
        normalized_comment = None

    if user.is_psychologist:
        if slot.psychologist_id != user.id:
            raise ForbiddenError("You can cancel only your own slot")

        if normalized_comment is None:
            raise ValidationError("Comment is required for psychologist cancellation")
    else:
        if latest_event.patient_id != user.id:
            raise ForbiddenError("You can cancel only your own booking")
        
    has_joined_participant = await has_joined_call_event_for_slot(
        db=db,
        slot_id=slot.id,
    )

    if has_joined_participant:
        raise ConflictError(
            "Booking cannot be cancelled after a participant joined the call"
        )

    await create_slot_event(
        db=db,
        slot_id=slot_id,
        event_type=SlotEventType.CANCELLED,
        patient_id=latest_event.patient_id,
        performed_by_id=user.id,
        comment=normalized_comment,
    )

    await db.commit()
    await db.refresh(slot)

    return slot

async def get_my_booked_slots(
    db: AsyncSession,
    user: User,
) -> list[tuple[Slot, SlotEvent | None]]:
    if user.is_psychologist:
        raise ForbiddenError("Only patients can view their bookings")

    slots_with_events = await get_slots_with_latest_events(db=db)

    now = datetime.now(timezone.utc)

    return [
        (slot, latest_event)
        for slot, latest_event in slots_with_events
        if (
            slot.end_at > now
            and latest_event is not None
            and latest_event.event_type == SlotEventType.BOOKED
            and latest_event.patient_id == user.id
        )
    ]

async def get_slot_history(
    db: AsyncSession,
    user: User,
) -> list[tuple[Slot, SlotEvent]]:
    return await get_slot_history_events(
        db=db,
        user_id=user.id,
        is_psychologist=user.is_psychologist,
    )

async def cleanup_expired_unbooked_slots(
    db: AsyncSession,
    *,
    retention_days: int = 7,
    limit: int = 500,
) -> int:
    cutoff = datetime.now(timezone.utc) - timedelta(
        days=retention_days,
    )

    booked_event_exists = exists(
        select(SlotEvent.id).where(
            SlotEvent.slot_id == Slot.id,
            SlotEvent.event_type == SlotEventType.BOOKED,
        )
    )

    result = await db.execute(
        select(Slot.id)
        .where(
            Slot.end_at < cutoff,
            ~booked_event_exists,
        )
        .order_by(Slot.end_at.asc())
        .limit(limit)
        .with_for_update(
            skip_locked=True,
        )
    )

    slot_ids = list(result.scalars().all())

    if not slot_ids:
        await db.rollback()
        return 0

    await db.execute(
        delete(Slot).where(
            Slot.id.in_(slot_ids),
        )
    )

    await db.commit()

    return len(slot_ids)

