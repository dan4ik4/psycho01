import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased
from sqlalchemy import func
from typing import Literal

from app.models.patient_assignment import PatientAssignment
from app.models.patient_assignment_event import (
    PatientAssignmentEvent,
    PatientAssignmentEventType,
)


async def get_assignment_by_pair(
    db: AsyncSession,
    patient_id: uuid.UUID,
    psychologist_id: uuid.UUID,
) -> PatientAssignment | None:
    result = await db.execute(
        select(PatientAssignment).where(
            PatientAssignment.patient_id == patient_id,
            PatientAssignment.psychologist_id == psychologist_id,
        )
    )
    return result.scalar_one_or_none()

async def get_assignment_by_id(
    db: AsyncSession,
    assignment_id: uuid.UUID,
) -> PatientAssignment | None:
    result = await db.execute(
        select(PatientAssignment).where(
            PatientAssignment.id == assignment_id,
        )
    )

    return result.scalar_one_or_none()

async def get_latest_assignment_event(
    db: AsyncSession,
    assignment_id: uuid.UUID,
) -> PatientAssignmentEvent | None:
    result = await db.execute(
        select(PatientAssignmentEvent)
        .where(PatientAssignmentEvent.assignment_id == assignment_id)
        .order_by(PatientAssignmentEvent.created_at.desc())
        .limit(1)
    )

    return result.scalar_one_or_none()


async def create_assignment(
    db: AsyncSession,
    patient_id: uuid.UUID,
    psychologist_id: uuid.UUID,
) -> PatientAssignment:
    assignment = PatientAssignment(
        patient_id=patient_id,
        psychologist_id=psychologist_id,
    )

    db.add(assignment)
    await db.flush()

    return assignment


async def create_assignment_event(
    db: AsyncSession,
    assignment_id: uuid.UUID,
    event_type: PatientAssignmentEventType,
    performed_by_id: uuid.UUID | None,
    comment: str | None = None,
) -> PatientAssignmentEvent:
    event = PatientAssignmentEvent(
        assignment_id=assignment_id,
        event_type=event_type,
        performed_by_id=performed_by_id,
        comment=comment,
    )

    db.add(event)
    await db.flush()

    return event

#latest event
async def get_assignments_by_latest_event(
    db: AsyncSession,
    user_id: uuid.UUID,
    event_types: list[PatientAssignmentEventType],
    role_filter: Literal["patient", "psychologist"] | None = None,
) -> list[PatientAssignment]:
    latest_event_subquery = (
        select(
            PatientAssignmentEvent.assignment_id,
            func.max(PatientAssignmentEvent.created_at).label("max_created_at"),
        )
        .group_by(PatientAssignmentEvent.assignment_id)
        .subquery()
    )

    latest_event = aliased(PatientAssignmentEvent)

    if role_filter == "psychologist":
        user_filter = PatientAssignment.psychologist_id == user_id

    elif role_filter == "patient":
        user_filter = PatientAssignment.patient_id == user_id

    else:
        user_filter = (
            (PatientAssignment.patient_id == user_id)
            | (PatientAssignment.psychologist_id == user_id)
        )

    result = await db.execute(
        select(PatientAssignment)
        .join(
            latest_event_subquery,
            PatientAssignment.id == latest_event_subquery.c.assignment_id,
        )
        .join(
            latest_event,
            (latest_event.assignment_id == latest_event_subquery.c.assignment_id)
            & (
                latest_event.created_at
                == latest_event_subquery.c.max_created_at
            ),
        )
        .where(
            user_filter,
            latest_event.event_type.in_(event_types),
        )
        .order_by(latest_event.created_at.desc())
    )

    return list(result.scalars().all())


async def get_finished_assignments(
    db: AsyncSession,
    user_id: uuid.UUID,
) -> list[PatientAssignment]:
    return await get_assignments_by_latest_event(
        db=db,
        user_id=user_id,
        event_types=[PatientAssignmentEventType.FINISHED],
    )


async def get_incoming_assignment_requests(
    db: AsyncSession,
    psychologist_id: uuid.UUID,
) -> list[PatientAssignment]:
    return await get_assignments_by_latest_event(
        db=db,
        user_id=psychologist_id,
        event_types=[PatientAssignmentEventType.REQUESTED],
        role_filter="psychologist",
    )


async def get_active_assignments(
    db: AsyncSession,
    user_id: uuid.UUID,
) -> list[PatientAssignment]:
    return await get_assignments_by_latest_event(
        db=db,
        user_id=user_id,
        event_types=[PatientAssignmentEventType.ACCEPTED],
    )


async def get_active_or_pending_patient_assignment(
    db: AsyncSession,
    patient_id: uuid.UUID,
) -> PatientAssignment | None:
    assignments = await get_assignments_by_latest_event(
        db=db,
        user_id=patient_id,
        event_types=[
            PatientAssignmentEventType.REQUESTED,
            PatientAssignmentEventType.ACCEPTED,
        ],
        role_filter="patient",
    )

    return assignments[0] if assignments else None

async def get_assignments_with_latest_events(
    db: AsyncSession,
    assignments: list[PatientAssignment],
) -> list[dict]:
    result = []

    for assignment in assignments:
        latest_event = await get_latest_assignment_event(
            db=db,
            assignment_id=assignment.id,
        )

        result.append(
            {
                "id": assignment.id,
                "patient_id": assignment.patient_id,
                "psychologist_id": assignment.psychologist_id,
                "latest_event": latest_event,
            }
        )

    return result

async def get_latest_patient_assignment(
    db: AsyncSession,
    patient_id: uuid.UUID,
) -> PatientAssignment | None:
    assignments = await get_assignments_by_latest_event(
        db=db,
        user_id=patient_id,
        event_types=[
            PatientAssignmentEventType.REQUESTED,
            PatientAssignmentEventType.ACCEPTED,
            PatientAssignmentEventType.REJECTED,
            PatientAssignmentEventType.FINISHED,
            PatientAssignmentEventType.CANCELLED,
        ],
        role_filter="patient",
    )

    if not assignments:
        return None

    return assignments[0]