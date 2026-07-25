import uuid

from sqlalchemy.ext.asyncio import AsyncSession
from typing import Literal
from sqlalchemy import func, select

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
        .order_by(
            PatientAssignmentEvent.created_at.desc(),
            PatientAssignmentEvent.id.desc(),
        )
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
) -> list[tuple[PatientAssignment, PatientAssignmentEvent]]:
    ranked_events_subquery = (
        select(
            PatientAssignmentEvent.id.label("event_id"),
            PatientAssignmentEvent.assignment_id.label("assignment_id"),
            func.row_number()
            .over(
                partition_by=PatientAssignmentEvent.assignment_id,
                order_by=(
                    PatientAssignmentEvent.created_at.desc(),
                    PatientAssignmentEvent.id.desc(),
                ),
            )
            .label("event_position"),
        )
        .subquery()
    )

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
        select(
            PatientAssignment,
            PatientAssignmentEvent,
        )
        .join(
            ranked_events_subquery,
            PatientAssignment.id
            == ranked_events_subquery.c.assignment_id,
        )
        .join(
            PatientAssignmentEvent,
            PatientAssignmentEvent.id
            == ranked_events_subquery.c.event_id,
        )
        .where(
            ranked_events_subquery.c.event_position == 1,
            user_filter,
            PatientAssignmentEvent.event_type.in_(event_types),
        )
        .order_by(
            PatientAssignmentEvent.created_at.desc(),
            PatientAssignmentEvent.id.desc(),
        )
    )

    return [
        (assignment, latest_event)
        for assignment, latest_event in result.all()
    ]


async def get_finished_assignments(
    db: AsyncSession,
    user_id: uuid.UUID,
) -> list[tuple[PatientAssignment, PatientAssignmentEvent]]:
    return await get_assignments_by_latest_event(
        db=db,
        user_id=user_id,
        event_types=[
            PatientAssignmentEventType.FINISHED,
            PatientAssignmentEventType.REJECTED,
            PatientAssignmentEventType.CANCELLED,
        ],
    )


async def get_incoming_assignment_requests(
    db: AsyncSession,
    psychologist_id: uuid.UUID,
) -> list[tuple[PatientAssignment, PatientAssignmentEvent]]:
    return await get_assignments_by_latest_event(
        db=db,
        user_id=psychologist_id,
        event_types=[PatientAssignmentEventType.REQUESTED],
        role_filter="psychologist",
    )


async def get_active_assignments(
    db: AsyncSession,
    psychologist_id: uuid.UUID,
) -> list[tuple[PatientAssignment, PatientAssignmentEvent]]:
    return await get_assignments_by_latest_event(
        db=db,
        user_id=psychologist_id,
        event_types=[PatientAssignmentEventType.ACCEPTED],
        role_filter="psychologist",
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

    if not assignments:
        return None

    assignment, _ = assignments[0]

    return assignment


async def get_latest_patient_assignment(
    db: AsyncSession,
    patient_id: uuid.UUID,
) -> tuple[PatientAssignment, PatientAssignmentEvent] | None:
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