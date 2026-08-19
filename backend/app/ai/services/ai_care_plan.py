import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from app.ai.crud.ai_care_plan import (
    create_ai_care_plan,
    create_ai_care_plan_version,
    create_ai_care_plan_event,
    get_ai_care_plan_by_assignment_id,
    get_ai_care_plan_version,
    get_latest_ai_care_plan_event,
    get_latest_ai_care_plan_version,
)
from app.ai.models.ai_care_plan import (
    AiCarePlan,
    AiCarePlanVersion,
    AiCarePlanEvent,
    AiCarePlanEventType,
)
from app.crud.patient_assignment import (
    get_assignment_by_id,
    get_latest_assignment_event,
)
from app.models.patient_assignment_event import (
    PatientAssignmentEventType,
)
from app.core.errors import (
    ConflictError,
    ForbiddenError,
    InternalError,
    NotFoundError,
)


async def _validate_active_assignment_for_psychologist(
    db: AsyncSession,
    assignment_id: uuid.UUID,
    psychologist_id: uuid.UUID,
) -> None:
    assignment = await get_assignment_by_id(
        db=db,
        assignment_id=assignment_id,
        for_update=True,
    )

    if assignment is None:
        raise NotFoundError("Assignment not found")

    if assignment.psychologist_id != psychologist_id:
        raise ForbiddenError(
            "You are not allowed to manage this care plan"
        )

    latest_event = await get_latest_assignment_event(
        db=db,
        assignment_id=assignment_id,
    )

    if (
        latest_event is None
        or latest_event.event_type
        != PatientAssignmentEventType.ACCEPTED
    ):
        raise ConflictError("Assignment is not active")

async def create_care_plan(
    db: AsyncSession,
    assignment_id: uuid.UUID,
    psychologist_id: uuid.UUID,
    instructions_for_ai: str,
    patient_recommendations: str | None,
) -> tuple[AiCarePlan, AiCarePlanVersion]:
    await _validate_active_assignment_for_psychologist(
        db=db,
        assignment_id=assignment_id,
        psychologist_id=psychologist_id,
    )

    existing_care_plan = await get_ai_care_plan_by_assignment_id(
        session=db,
        assignment_id=assignment_id,
    )

    if existing_care_plan is not None:
        raise ConflictError(
            "Care plan already exists for this assignment"
        )

    care_plan = await create_ai_care_plan(
        session=db,
        assignment_id=assignment_id,
        created_by_id=psychologist_id,
    )

    version = await create_ai_care_plan_version(
        session=db,
        care_plan_id=care_plan.id,
        version=1,
        instructions_for_ai=instructions_for_ai,
        patient_recommendations=patient_recommendations,
        created_by_id=psychologist_id,
    )

    await db.commit()
    await db.refresh(care_plan)
    await db.refresh(version)

    return care_plan, version

async def activate_care_plan_version(
    db: AsyncSession,
    assignment_id: uuid.UUID,
    psychologist_id: uuid.UUID,
    version_id: uuid.UUID,
    comment: str | None = None,
) -> AiCarePlanEvent:
    await _validate_active_assignment_for_psychologist(
        db=db,
        assignment_id=assignment_id,
        psychologist_id=psychologist_id,
    )

    care_plan = await get_ai_care_plan_by_assignment_id(
        session=db,
        assignment_id=assignment_id,
        for_update=True,
    )

    if care_plan is None:
        raise NotFoundError("Care plan not found")

    version = await get_ai_care_plan_version(
        session=db,
        care_plan_id=care_plan.id,
        version_id=version_id,
    )

    if version is None:
        raise NotFoundError("Care plan version not found")

    latest_care_plan_event = await get_latest_ai_care_plan_event(
        session=db,
        care_plan_id=care_plan.id,
    )

    if (
        latest_care_plan_event is not None
        and latest_care_plan_event.event_type
        == AiCarePlanEventType.COMPLETED
    ):
        raise ConflictError("Care plan is completed")

    if (
        latest_care_plan_event is not None
        and latest_care_plan_event.event_type
        == AiCarePlanEventType.ACTIVATED
        and latest_care_plan_event.version_id == version.id
    ):
        raise ConflictError(
            "Care plan version is already active"
        )

    event = await create_ai_care_plan_event(
        session=db,
        care_plan_id=care_plan.id,
        version_id=version.id,
        event_type=AiCarePlanEventType.ACTIVATED,
        performed_by_id=psychologist_id,
        comment=comment,
    )

    await db.commit()
    await db.refresh(event)

    return event

async def create_new_care_plan_version(
    db: AsyncSession,
    assignment_id: uuid.UUID,
    psychologist_id: uuid.UUID,
    instructions_for_ai: str,
    patient_recommendations: str | None,
) -> AiCarePlanVersion:
    await _validate_active_assignment_for_psychologist(
        db=db,
        assignment_id=assignment_id,
        psychologist_id=psychologist_id,
    )

    care_plan = await get_ai_care_plan_by_assignment_id(
        session=db,
        assignment_id=assignment_id,
        for_update=True,
    )

    if care_plan is None:
        raise NotFoundError("Care plan not found")

    latest_care_plan_event = await get_latest_ai_care_plan_event(
        session=db,
        care_plan_id=care_plan.id,
    )

    if (
        latest_care_plan_event is not None
        and latest_care_plan_event.event_type
        == AiCarePlanEventType.COMPLETED
    ):
        raise ConflictError("Care plan is completed")

    latest_version = await get_latest_ai_care_plan_version(
        session=db,
        care_plan_id=care_plan.id,
    )

    if latest_version is None:
        raise InternalError("Care plan has no versions")

    version = await create_ai_care_plan_version(
        session=db,
        care_plan_id=care_plan.id,
        version=latest_version.version + 1,
        instructions_for_ai=instructions_for_ai,
        patient_recommendations=patient_recommendations,
        created_by_id=psychologist_id,
    )

    await db.commit()
    await db.refresh(version)

    return version

async def pause_care_plan(
    db: AsyncSession,
    assignment_id: uuid.UUID,
    psychologist_id: uuid.UUID,
    comment: str | None = None,
) -> AiCarePlanEvent:
    await _validate_active_assignment_for_psychologist(
        db=db,
        assignment_id=assignment_id,
        psychologist_id=psychologist_id,
    )

    care_plan = await get_ai_care_plan_by_assignment_id(
        session=db,
        assignment_id=assignment_id,
        for_update=True,
    )

    if care_plan is None:
        raise NotFoundError("Care plan not found")

    latest_care_plan_event = await get_latest_ai_care_plan_event(
        session=db,
        care_plan_id=care_plan.id,
    )

    if latest_care_plan_event is None:
        raise ConflictError("Care plan is not active")

    if (
        latest_care_plan_event.event_type
        == AiCarePlanEventType.COMPLETED
    ):
        raise ConflictError("Care plan is completed")

    if (
        latest_care_plan_event.event_type
        == AiCarePlanEventType.PAUSED
    ):
        raise ConflictError("Care plan is already paused")

    if (
        latest_care_plan_event.event_type
        != AiCarePlanEventType.ACTIVATED
    ):
        raise ConflictError("Care plan is not active")

    event = await create_ai_care_plan_event(
        session=db,
        care_plan_id=care_plan.id,
        version_id=latest_care_plan_event.version_id,
        event_type=AiCarePlanEventType.PAUSED,
        performed_by_id=psychologist_id,
        comment=comment,
    )

    await db.commit()
    await db.refresh(event)

    return event

async def complete_care_plan(
    db: AsyncSession,
    assignment_id: uuid.UUID,
    psychologist_id: uuid.UUID,
    comment: str | None = None,
) -> AiCarePlanEvent:
    assignment = await get_assignment_by_id(
        db=db,
        assignment_id=assignment_id,
        for_update=True,
    )

    if assignment is None:
        raise NotFoundError("Assignment not found")

    if assignment.psychologist_id != psychologist_id:
        raise ForbiddenError(
            "You are not allowed to complete this care plan"
        )

    care_plan = await get_ai_care_plan_by_assignment_id(
        session=db,
        assignment_id=assignment_id,
        for_update=True,
    )

    if care_plan is None:
        raise NotFoundError("Care plan not found")

    latest_care_plan_event = await get_latest_ai_care_plan_event(
        session=db,
        care_plan_id=care_plan.id,
    )

    if latest_care_plan_event is None:
        raise ConflictError(
            "Care plan has not been activated"
        )

    if (
        latest_care_plan_event.event_type
        == AiCarePlanEventType.COMPLETED
    ):
        raise ConflictError(
            "Care plan is already completed"
        )

    event = await create_ai_care_plan_event(
        session=db,
        care_plan_id=care_plan.id,
        version_id=latest_care_plan_event.version_id,
        event_type=AiCarePlanEventType.COMPLETED,
        performed_by_id=psychologist_id,
        comment=comment,
    )

    await db.commit()
    await db.refresh(event)

    return event

async def get_patient_care_plan(
    db: AsyncSession,
    assignment_id: uuid.UUID,
    patient_id: uuid.UUID,
) -> tuple[
    AiCarePlan,
    AiCarePlanVersion,
    AiCarePlanEvent,
]:
    assignment = await get_assignment_by_id(
        db=db,
        assignment_id=assignment_id,
    )

    if assignment is None:
        raise NotFoundError("Assignment not found")

    if assignment.patient_id != patient_id:
        raise ForbiddenError(
            "You are not allowed to access this care plan"
        )

    care_plan = await get_ai_care_plan_by_assignment_id(
        session=db,
        assignment_id=assignment_id,
    )

    if care_plan is None:
        raise NotFoundError("Care plan not found")

    latest_event = await get_latest_ai_care_plan_event(
        session=db,
        care_plan_id=care_plan.id,
    )

    if latest_event is None:
        raise ConflictError(
            "Care plan is not available yet"
        )

    version = await get_ai_care_plan_version(
        session=db,
        care_plan_id=care_plan.id,
        version_id=latest_event.version_id,
    )

    if version is None:
        raise InternalError(
            "Care plan version not found"
        )

    return care_plan, version, latest_event

async def get_psychologist_care_plan(
    db: AsyncSession,
    assignment_id: uuid.UUID,
    psychologist_id: uuid.UUID,
) -> tuple[
    AiCarePlan,
    AiCarePlanVersion,
    AiCarePlanEvent | None,
]:
    assignment = await get_assignment_by_id(
        db=db,
        assignment_id=assignment_id,
    )

    if assignment is None:
        raise NotFoundError("Assignment not found")

    if assignment.psychologist_id != psychologist_id:
        raise ForbiddenError(
            "You are not allowed to access this care plan"
        )

    care_plan = await get_ai_care_plan_by_assignment_id(
        session=db,
        assignment_id=assignment_id,
    )

    if care_plan is None:
        raise NotFoundError("Care plan not found")

    latest_version = await get_latest_ai_care_plan_version(
        session=db,
        care_plan_id=care_plan.id,
    )

    if latest_version is None:
        raise InternalError(
            "Care plan has no versions"
        )

    latest_event = await get_latest_ai_care_plan_event(
        session=db,
        care_plan_id=care_plan.id,
    )

    return care_plan, latest_version, latest_event

