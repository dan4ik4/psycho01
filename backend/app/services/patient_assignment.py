import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.patient_assignment import PatientAssignment
from app.models.patient_assignment_event import PatientAssignmentEventType
from app.crud.patient_assignment import (
    get_assignment_by_pair,
    create_assignment,
    get_latest_assignment_event,
    create_assignment_event,
    get_assignment_by_id,
    get_active_or_pending_patient_assignment,
)
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
    )

    if psychologist is None:
        raise ValueError("Psychologist not found")

    if not psychologist.is_psychologist:
        raise ValueError("Selected user is not a psychologist")
    
    if not comment.strip():
        raise ValueError("Comment is required")

    current_assignment = await get_active_or_pending_patient_assignment(
    db=db,
    patient_id=patient_id,
)

    if current_assignment is not None:
        raise ValueError("Patient already has pending or active assignment")
    
    assignment = await get_assignment_by_pair(
        db=db,
        patient_id=patient_id,
        psychologist_id=psychologist_id,
    )

    if assignment is None:
        assignment = await create_assignment(
            db=db,
            patient_id=patient_id,
            psychologist_id=psychologist_id,
        )
    else:
        latest_event = await get_latest_assignment_event(
            db=db,
            assignment_id=assignment.id,
        )

        if latest_event and latest_event.event_type in (
            PatientAssignmentEventType.REQUESTED,
            PatientAssignmentEventType.ACCEPTED,
        ):
            raise ValueError("Assignment request already exists or is active")

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
        raise ValueError("Comment is required")
    
    assignment = await get_assignment_by_id(
        db=db,
        assignment_id=assignment_id,
    )

    if assignment is None:
        raise ValueError("Assignment not found")

    if assignment.psychologist_id != psychologist_id:
        raise ValueError("You are not allowed to accept this assignment")
    
    latest_event = await get_latest_assignment_event(
        db=db,
        assignment_id=assignment_id,
    )

    if latest_event is None or latest_event.event_type != PatientAssignmentEventType.REQUESTED:
        raise ValueError("Assignment request is not pending")

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
    )

    if assignment is None:
        raise ValueError("Assignment not found")

    if assignment.psychologist_id != psychologist_id:
        raise ValueError("You are not allowed to accept this assignment")
    
    latest_event = await get_latest_assignment_event(
        db=db,
        assignment_id=assignment_id,
    )

    if latest_event is None or latest_event.event_type != PatientAssignmentEventType.REQUESTED:
        raise ValueError("Assignment request is not pending")

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
        raise ValueError("Comment is required")

    assignment = await get_assignment_by_id(
        db=db,
        assignment_id=assignment_id,
    )

    if performed_by_id not in (
        assignment.patient_id,
        assignment.psychologist_id,
    ):
        raise ValueError("You are not allowed to finish this assignment")

    latest_event = await get_latest_assignment_event(
        db=db,
        assignment_id=assignment_id,
    )

    if latest_event is None or latest_event.event_type != PatientAssignmentEventType.ACCEPTED:
        raise ValueError("Assignment is not active")

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
    )

    if assignment is None:
        raise ValueError("Assignment not found")

    if assignment.patient_id != patient_id:
        raise ValueError("You are not allowed to cancel this assignment request")

    latest_event = await get_latest_assignment_event(
        db=db,
        assignment_id=assignment_id,
    )

    if latest_event is None or latest_event.event_type != PatientAssignmentEventType.REQUESTED:
        raise ValueError("Only pending assignment request can be cancelled")

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