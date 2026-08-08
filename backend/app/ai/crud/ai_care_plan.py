import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.ai.models.ai_care_plan import (
    AiCarePlan,
    AiCarePlanVersion,
    AiCarePlanEvent,
    AiCarePlanEventType,
)


async def get_ai_care_plan_by_assignment_id(
    session: AsyncSession,
    assignment_id: uuid.UUID,
) -> AiCarePlan | None:
    result = await session.execute(
        select(AiCarePlan).where(
            AiCarePlan.assignment_id == assignment_id,
        )
    )

    return result.scalar_one_or_none()

async def create_ai_care_plan(
    session: AsyncSession,
    assignment_id: uuid.UUID,
    created_by_id: uuid.UUID,
) -> AiCarePlan:
    care_plan = AiCarePlan(
        assignment_id=assignment_id,
        created_by_id=created_by_id,
    )

    session.add(care_plan)
    await session.flush()

    return care_plan

async def create_ai_care_plan_version(
    session: AsyncSession,
    care_plan_id: uuid.UUID,
    version: int,
    instructions_for_ai: str,
    patient_recommendations: str | None,
    created_by_id: uuid.UUID,
) -> AiCarePlanVersion:
    care_plan_version = AiCarePlanVersion(
        care_plan_id=care_plan_id,
        version=version,
        instructions_for_ai=instructions_for_ai,
        patient_recommendations=patient_recommendations,
        created_by_id=created_by_id,
    )

    session.add(care_plan_version)
    await session.flush()

    return care_plan_version

async def create_ai_care_plan_event(
    session: AsyncSession,
    care_plan_id: uuid.UUID,
    version_id: uuid.UUID,
    event_type: AiCarePlanEventType,
    performed_by_id: uuid.UUID,
    comment: str | None = None,
) -> AiCarePlanEvent:
    event = AiCarePlanEvent(
        care_plan_id=care_plan_id,
        version_id=version_id,
        event_type=event_type,
        performed_by_id=performed_by_id,
        comment=comment,
    )

    session.add(event)
    await session.flush()

    return event

async def get_latest_ai_care_plan_event(
    session: AsyncSession,
    care_plan_id: uuid.UUID,
) -> AiCarePlanEvent | None:
    result = await session.execute(
        select(AiCarePlanEvent)
        .where(
            AiCarePlanEvent.care_plan_id == care_plan_id,
        )
        .order_by(
            AiCarePlanEvent.created_at.desc(),
            AiCarePlanEvent.id.desc(),
        )
        .limit(1)
    )

    return result.scalar_one_or_none()

async def get_ai_care_plan_version(
    session: AsyncSession,
    care_plan_id: uuid.UUID,
    version_id: uuid.UUID,
) -> AiCarePlanVersion | None:
    result = await session.execute(
        select(AiCarePlanVersion).where(
            AiCarePlanVersion.id == version_id,
            AiCarePlanVersion.care_plan_id == care_plan_id,
        )
    )

    return result.scalar_one_or_none()

async def get_latest_ai_care_plan_version(
    session: AsyncSession,
    care_plan_id: uuid.UUID,
) -> AiCarePlanVersion | None:
    result = await session.execute(
        select(AiCarePlanVersion)
        .where(
            AiCarePlanVersion.care_plan_id == care_plan_id,
        )
        .order_by(
            AiCarePlanVersion.version.desc(),
        )
        .limit(1)
    )

    return result.scalar_one_or_none()

