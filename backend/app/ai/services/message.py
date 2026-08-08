import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from app.ai.crud.conversation import get_ai_conversation_for_patient
from app.ai.crud.message import (
    create_ai_message,
    get_ai_messages_for_conversation,
)
from app.ai.models.message import AiMessage, AiMessageRole
from app.ai.providers.chat import ChatMessage, generate_ai_reply
from app.ai.crud.ai_care_plan import (
    get_ai_care_plan_by_assignment_id,
    get_ai_care_plan_version,
    get_latest_ai_care_plan_event,
)
from app.ai.models.ai_care_plan import AiCarePlanEventType
from app.ai.models.conversation import AiConversationMode
from app.crud.patient_assignment import get_latest_assignment_event
from app.models.patient_assignment_event import PatientAssignmentEventType


async def send_user_message(
    db: AsyncSession,
    conversation_id: uuid.UUID,
    patient_id: uuid.UUID,
    content: str,
) -> dict[str, AiMessage]:
    conversation = await get_ai_conversation_for_patient(
        session=db,
        conversation_id=conversation_id,
        patient_id=patient_id,
    )

    if conversation is None:
        raise ValueError("Conversation not found")

    normalized_content = content.strip()

    if not normalized_content:
        raise ValueError("Message content cannot be empty")
    
    guided_instructions = None

    if conversation.mode == AiConversationMode.GUIDED:
        if conversation.assignment_id is None:
            raise ValueError(
                "Guided conversation has no psychologist assignment"
            )

        latest_assignment_event = await get_latest_assignment_event(
            db=db,
            assignment_id=conversation.assignment_id,
        )

        if (
            latest_assignment_event is None
            or latest_assignment_event.event_type
            != PatientAssignmentEventType.ACCEPTED
        ):
            raise ValueError(
                "Guided conversation is no longer available"
            )

        care_plan = await get_ai_care_plan_by_assignment_id(
            session=db,
            assignment_id=conversation.assignment_id,
        )

        if care_plan is None:
            raise ValueError(
                "Guided conversation has no care plan"
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
            raise ValueError(
                "Guided conversation is currently unavailable"
            )

        active_version = await get_ai_care_plan_version(
            session=db,
            care_plan_id=care_plan.id,
            version_id=latest_care_plan_event.version_id,
        )

        if active_version is None:
            raise ValueError(
                "Active care plan version not found"
            )

        guided_instructions = active_version.instructions_for_ai

    user_message = await create_ai_message(
        session=db,
        conversation_id=conversation.id,
        role=AiMessageRole.USER,
        content=normalized_content,
    )

    # Сохраняем сообщение пользователя отдельно.
    # Если AI упадёт, сообщение всё равно останется в истории.
    await db.commit()
    await db.refresh(user_message)

    message_history = await get_ai_messages_for_conversation(
        session=db,
        conversation_id=conversation.id,
    )

    provider_messages: list[ChatMessage] = []

    for message in message_history:
        role = (
            "user"
            if message.role == AiMessageRole.USER
            else "assistant"
        )

        provider_messages.append(
            {
                "role": role,
                "content": message.content,
            }
        )

    assistant_content = await generate_ai_reply(
        messages=provider_messages,
        guided_instructions=guided_instructions,
    )

    assistant_message = await create_ai_message(
        session=db,
        conversation_id=conversation.id,
        role=AiMessageRole.ASSISTANT,
        content=assistant_content,
    )

    await db.commit()
    await db.refresh(assistant_message)

    return {
        "user_message": user_message,
        "assistant_message": assistant_message,
    }