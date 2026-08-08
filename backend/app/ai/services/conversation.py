from sqlalchemy.ext.asyncio import AsyncSession
import uuid

from app.ai.models.conversation import AiConversation, AiConversationMode
from app.crud.patient_assignment import get_latest_patient_assignment
from app.models.patient_assignment_event import PatientAssignmentEventType
from app.models.user import User
from app.ai.crud.conversation import (
    create_ai_conversation,
    get_ai_conversation_for_patient,
    get_ai_conversations_for_patient,
    get_ai_conversation_with_messages_for_patient,
    rename_ai_conversation,
)


async def create_conversation(
    db: AsyncSession,
    user: User,
    name: str | None,
    mode: AiConversationMode,
) -> AiConversation:

    if user.is_psychologist:
        raise ValueError(
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
            raise ValueError(
                "Guided conversation requires an active psychologist assignment"
            )

        assignment, latest_event = assignment_data

        if (
            latest_event.event_type
            != PatientAssignmentEventType.ACCEPTED
        ):
            raise ValueError(
                "Guided conversation requires an active psychologist assignment"
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
        raise ValueError("Only patients can access AI conversations")

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
        raise ValueError("Only patients can rename AI conversations")

    conversation = await get_ai_conversation_for_patient(
        session=db,
        conversation_id=conversation_id,
        patient_id=user.id,
    )

    if conversation is None:
        raise ValueError("Conversation not found")

    normalized_name = name.strip()

    if not normalized_name:
        raise ValueError("Conversation name cannot be empty")

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
        raise ValueError(
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
        raise ValueError("Conversation not found")

    return conversation

