from sqlalchemy.ext.asyncio import AsyncSession
import uuid

from app.ai.models.conversation import AiConversation, AiConversationMode
from app.crud.patient_assignment import (
    get_latest_patient_assignment,
    get_assignment_by_id,
    get_latest_assignment_event,
)
from app.models.patient_assignment_event import PatientAssignmentEventType
from app.models.user import User
from app.ai.crud.conversation import (
    create_ai_conversation,
    get_ai_conversation_for_patient,
    get_ai_conversations_for_patient,
    get_ai_conversation_with_messages_for_patient,
    rename_ai_conversation,
)
from app.ai.crud.ai_care_plan import (
    get_ai_care_plan_by_assignment_id,
    get_latest_ai_care_plan_event,
)
from app.core.errors import (
    ConflictError,
    ForbiddenError,
    NotFoundError,
    ValidationError,
)
from app.ai.models.ai_care_plan import AiCarePlanEventType


async def create_conversation(
    db: AsyncSession,
    user: User,
    name: str | None,
    mode: AiConversationMode,
) -> AiConversation:

    if user.is_psychologist:
        raise ForbiddenError(
            "Only patients can create AI conversations"
        )

    conversation_name = (
        name.strip()
        if name is not None and name.strip()
        else "Новый чат"
    )

    assignment_id = None

    if mode == AiConversationMode.GUIDED:
        assignment_data = await get_latest_patient_assignment(
            db=db,
            patient_id=user.id,
        )

        if assignment_data is None:
            raise ConflictError(
                "Guided conversation requires an active psychologist assignment"
            )

        assignment, latest_event = assignment_data

        assignment = await get_assignment_by_id(
            db=db,
            assignment_id=assignment.id,
            for_update=True,
        )

        if assignment is None:
            raise ConflictError(
                "Guided conversation requires an active psychologist assignment"
            )

        latest_event = await get_latest_assignment_event(
            db=db,
            assignment_id=assignment.id,
        )

        if (
            latest_event.event_type
            != PatientAssignmentEventType.ACCEPTED
        ):
            raise ConflictError(
                "Guided conversation requires an active psychologist assignment"
            )

        care_plan = await get_ai_care_plan_by_assignment_id(
            session=db,
            assignment_id=assignment.id,
        )

        if care_plan is None:
            raise ConflictError(
                "Guided conversation requires an active care plan"
            )

        latest_care_plan_event = await get_latest_ai_care_plan_event(
            session=db,
            care_plan_id=care_plan.id,
        )

        if (
            latest_care_plan_event is None
            or latest_care_plan_event.event_type
            != AiCarePlanEventType.ACTIVATED
        ):
            raise ConflictError(
                "Guided conversation requires an active care plan"
            )

        assignment_id = assignment.id

    conversation = await create_ai_conversation(
        session=db,
        patient_id=user.id,
        name=conversation_name,
        mode=mode,
        assignment_id=assignment_id,
    )

    await db.commit()
    await db.refresh(conversation)

    return conversation

async def get_my_conversations(
    db: AsyncSession,
    user: User,
) -> list[AiConversation]:
    if user.is_psychologist:
        raise ForbiddenError("Only patients can access AI conversations")

    return await get_ai_conversations_for_patient(
        session=db,
        patient_id=user.id,
    )

async def rename_conversation(
    db: AsyncSession,
    user: User,
    conversation_id: uuid.UUID,
    name: str,
) -> AiConversation:
    if user.is_psychologist:
        raise ForbiddenError("Only patients can rename AI conversations")

    conversation = await get_ai_conversation_for_patient(
        session=db,
        conversation_id=conversation_id,
        patient_id=user.id,
    )

    if conversation is None:
        raise NotFoundError("Conversation not found")

    normalized_name = name.strip()

    if not normalized_name:
        raise ValidationError("Conversation name cannot be empty")

    conversation = await rename_ai_conversation(
        session=db,
        conversation=conversation,
        name=normalized_name,
    )

    await db.commit()
    await db.refresh(conversation)

    return conversation

async def get_conversation_with_messages(
    db: AsyncSession,
    user: User,
    conversation_id: uuid.UUID,
) -> AiConversation:
    if user.is_psychologist:
        raise ForbiddenError(
            "Only patients can access AI conversations"
        )

    conversation = (
        await get_ai_conversation_with_messages_for_patient(
            session=db,
            conversation_id=conversation_id,
            patient_id=user.id,
        )
    )

    if conversation is None:
        raise NotFoundError("Conversation not found")

    return conversation

