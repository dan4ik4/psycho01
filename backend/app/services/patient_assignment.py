import uuid
from datetime import datetime, timezone
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.patient_assignment import PatientAssignment
from app.models.patient_assignment_event import PatientAssignmentEventType
from app.crud.patient_assignment import (
    create_assignment,
    get_latest_assignment_event,
    create_assignment_event,
    get_assignment_by_id,
    get_active_or_pending_patient_assignment,
)
from app.crud.slot import (
    get_slots_with_latest_events,
    get_slot_by_id,
    get_latest_slot_event,
    create_slot_event,
)
from app.crud.call import has_joined_call_event_for_slot
from app.core.errors import (
    ConflictError,
    ForbiddenError,
    NotFoundError,
    ValidationError,
)
from app.models.slot_event import SlotEventType
from app.crud.user import get_user_by_id

async def request_assignment(
    db: AsyncSession,
    patient_id: uuid.UUID,
    psychologist_id: uuid.UUID,
    comment: str,
) -> PatientAssignment:
    psychologist = await get_user_by_id(
        db=db,
        user_id=psychologist_id,
        for_update=True,
    )

    if (
        psychologist is None
        or not psychologist.is_psychologist
        or not psychologist.is_active
    ):
        raise NotFoundError("Psychologist not found")
    
    if not comment.strip():
        raise ValidationError("Comment is required")
    
    patient = await get_user_by_id(
        db=db,
        user_id=patient_id,
        for_update=True,
    )

    if patient is None:
        raise NotFoundError("Patient not found")
    
    if not patient.is_active:
        raise ForbiddenError(
            "Inactive user cannot request an assignment"
        )

    if patient.is_psychologist:
        raise ForbiddenError(
            "Psychologist cannot request an assignment"
        )

    current_assignment = await get_active_or_pending_patient_assignment(
    db=db,
    patient_id=patient_id,
)

    if current_assignment is not None:
        raise ConflictError("Patient already has pending or active assignment")
    
    assignment = await create_assignment(
        db=db,
        patient_id=patient_id,
        psychologist_id=psychologist_id,
    )

    await create_assignment_event(
        db=db,
        assignment_id=assignment.id,
        event_type=PatientAssignmentEventType.REQUESTED,
        performed_by_id=patient_id,
        comment=comment,
    )

    await db.commit()
    await db.refresh(assignment)

    return assignment

async def reject_assignment(
    db: AsyncSession,
    assignment_id: uuid.UUID,
    psychologist_id: uuid.UUID,
    comment: str,
) -> PatientAssignment:
    if not comment.strip():
        raise ValidationError("Comment is required")
    
    assignment = await get_assignment_by_id(
        db=db,
        assignment_id=assignment_id,
        for_update=True,
    )

    if assignment is None:
        raise NotFoundError("Assignment not found")

    if assignment.psychologist_id != psychologist_id:
        raise ForbiddenError("You are not allowed to accept this assignment")
    
    psychologist = await get_user_by_id(
        db=db,
        user_id=psychologist_id,
        for_update=True,
    )

    if (
        psychologist is None
        or not psychologist.is_psychologist
        or not psychologist.is_active
    ):
        raise ForbiddenError(
            "Psychologist access is no longer available"
        )
    
    latest_event = await get_latest_assignment_event(
        db=db,
        assignment_id=assignment_id,
    )

    if latest_event is None or latest_event.event_type != PatientAssignmentEventType.REQUESTED:
        raise ConflictError("Assignment request is not pending")

    await create_assignment_event(
        db=db,
        assignment_id=assignment_id,
        event_type=PatientAssignmentEventType.REJECTED,
        performed_by_id=psychologist_id,
        comment=comment,
    )

    assignment = await get_assignment_by_id(
        db=db,
        assignment_id=assignment_id,
    )

    await db.commit()
    await db.refresh(assignment)

    return assignment


async def accept_assignment(
    db: AsyncSession,
    assignment_id: uuid.UUID,
    psychologist_id: uuid.UUID,
) -> PatientAssignment:
    assignment = await get_assignment_by_id(
        db=db,
        assignment_id=assignment_id,
        for_update=True,
    )

    if assignment is None:
        raise NotFoundError("Assignment not found")

    if assignment.psychologist_id != psychologist_id:
        raise ForbiddenError("You are not allowed to accept this assignment")
    
    psychologist = await get_user_by_id(
        db=db,
        user_id=psychologist_id,
        for_update=True,
    )

    if (
        psychologist is None
        or not psychologist.is_psychologist
        or not psychologist.is_active
    ):
        raise ForbiddenError(
            "Psychologist access is no longer available"
        )
    
    latest_event = await get_latest_assignment_event(
        db=db,
        assignment_id=assignment_id,
    )

    if latest_event is None or latest_event.event_type != PatientAssignmentEventType.REQUESTED:
        raise ConflictError("Assignment request is not pending")

    await create_assignment_event(
        db=db,
        assignment_id=assignment_id,
        event_type=PatientAssignmentEventType.ACCEPTED,
        performed_by_id=psychologist_id,
    )

    assignment = await get_assignment_by_id(db=db, assignment_id=assignment_id)

    await db.commit()
    await db.refresh(assignment)

    return assignment

async def finish_assignment(
    db: AsyncSession,
    assignment_id: uuid.UUID,
    performed_by_id: uuid.UUID,
    comment: str,
) -> PatientAssignment:
    if not comment.strip():
        raise ValidationError("Comment is required")

    assignment = await get_assignment_by_id(
        db=db,
        assignment_id=assignment_id,
        for_update=True,
    )

    if assignment is None:
        raise NotFoundError("Assignment not found")

    if performed_by_id not in (
        assignment.patient_id,
        assignment.psychologist_id,
    ):
        raise ForbiddenError("You are not allowed to finish this assignment")
    
    if performed_by_id == assignment.psychologist_id:
        psychologist = await get_user_by_id(
            db=db,
            user_id=performed_by_id,
            for_update=True,
        )

        if (
            psychologist is None
            or not psychologist.is_psychologist
            or not psychologist.is_active
        ):
            raise ForbiddenError(
                "Psychologist access is no longer available"
            )

    latest_event = await get_latest_assignment_event(
        db=db,
        assignment_id=assignment_id,
    )

    if latest_event is None or latest_event.event_type != PatientAssignmentEventType.ACCEPTED:
        raise ConflictError("Assignment is not active")
    
    now = datetime.now(timezone.utc)

    slots_with_events = await get_slots_with_latest_events(
        db=db,
        psychologist_id=assignment.psychologist_id,
    )

    for slot, latest_slot_event in slots_with_events:
        if (
            slot.start_at <= now
            or latest_slot_event is None
            or latest_slot_event.event_type != SlotEventType.BOOKED
            or latest_slot_event.patient_id != assignment.patient_id
        ):
            continue

        locked_slot = await get_slot_by_id(
            db=db,
            slot_id=slot.id,
            for_update=True,
        )

        if locked_slot is None:
            continue

        locked_latest_event = await get_latest_slot_event(
            db=db,
            slot_id=slot.id,
        )

        if (
            locked_latest_event is None
            or locked_latest_event.event_type != SlotEventType.BOOKED
            or locked_latest_event.patient_id != assignment.patient_id
        ):
            continue

        has_joined_participant = await has_joined_call_event_for_slot(
            db=db,
            slot_id=locked_slot.id,
        )

        if has_joined_participant:
            raise ConflictError(
                "Assignment cannot be finished after a participant joined the call"
            )

        await create_slot_event(
            db=db,
            slot_id=slot.id,
            event_type=SlotEventType.CANCELLED,
            patient_id=assignment.patient_id,
            performed_by_id=performed_by_id,
            comment="Automatically cancelled because assignment was finished",
        )

    await create_assignment_event(
        db=db,
        assignment_id=assignment_id,
        event_type=PatientAssignmentEventType.FINISHED,
        performed_by_id=performed_by_id,
        comment=comment,
    )

    assignment = await get_assignment_by_id(
        db=db,
        assignment_id=assignment_id,
    )

    await db.commit()
    await db.refresh(assignment)

    return assignment

async def cancel_assignment(
    db: AsyncSession,
    assignment_id: uuid.UUID,
    patient_id: uuid.UUID,
    comment: str | None = None,
) -> PatientAssignment:
    assignment = await get_assignment_by_id(
        db=db,
        assignment_id=assignment_id,
        for_update=True,
    )

    if assignment is None:
        raise NotFoundError("Assignment not found")

    if assignment.patient_id != patient_id:
        raise ForbiddenError("You are not allowed to cancel this assignment request")

    latest_event = await get_latest_assignment_event(
        db=db,
        assignment_id=assignment_id,
    )

    if latest_event is None or latest_event.event_type != PatientAssignmentEventType.REQUESTED:
        raise ConflictError("Only pending assignment request can be cancelled")

    await create_assignment_event(
        db=db,
        assignment_id=assignment_id,
        event_type=PatientAssignmentEventType.CANCELLED,
        performed_by_id=patient_id,
        comment=comment,
    )

    assignment = await get_assignment_by_id(
        db=db,
        assignment_id=assignment_id,
    )

    await db.commit()
    await db.refresh(assignment)

    return assignment

