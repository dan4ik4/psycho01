import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.settings import settings

from app.ai.crud.ai_care_plan import (
    get_ai_care_plan_by_assignment_id,
    get_ai_care_plan_version,
    get_latest_ai_care_plan_event,
)
from app.ai.crud.conversation import get_ai_conversation_for_patient
from app.ai.crud.message import (
    create_ai_message,
    get_ai_message_by_request_id,
    get_recent_ai_messages_for_conversation,
    has_ai_messages_after,
)
from app.ai.models.ai_care_plan import AiCarePlanEventType
from app.ai.models.conversation import AiConversationMode
from app.ai.models.message import AiMessage, AiMessageRole
from app.ai.providers.chat import (
    AiProviderError,
    ChatMessage,
    generate_ai_reply,
)
from app.crud.patient_assignment import (
    get_assignment_by_id,
    get_latest_assignment_event,
)
from app.core.errors import (
    ConflictError,
    ForbiddenError,
    NotFoundError,
    ValidationError,
)
from app.models.patient_assignment_event import PatientAssignmentEventType
from app.models.user import User


async def send_user_message(
    db: AsyncSession,
    conversation_id: uuid.UUID,
    user: User,
    content: str,
    request_id: uuid.UUID,
) -> dict[str, AiMessage]:
    if user.is_psychologist:
        raise ForbiddenError(
            "Only patients can use AI conversations"
        )

    conversation = await get_ai_conversation_for_patient(
        session=db,
        conversation_id=conversation_id,
        patient_id=user.id,
        for_update=True,
    )

    if conversation is None:
        raise NotFoundError("Conversation not found")

    normalized_content = content.strip()

    if not normalized_content:
        raise ValidationError(
            "Message content cannot be empty"
        )

    existing_user_message = await get_ai_message_by_request_id(
        session=db,
        conversation_id=conversation.id,
        request_id=request_id,
        role=AiMessageRole.USER,
    )

    existing_assistant_message = await get_ai_message_by_request_id(
        session=db,
        conversation_id=conversation.id,
        request_id=request_id,
        role=AiMessageRole.ASSISTANT,
    )

    if existing_user_message is not None:
        if existing_user_message.content != normalized_content:
            raise ConflictError(
                "Request id is already used for another message"
            )

        if existing_assistant_message is not None:
            return {
                "user_message": existing_user_message,
                "assistant_message": existing_assistant_message,
            }
        
        has_later_messages = await has_ai_messages_after(
            session=db,
            conversation_id=conversation.id,
            created_at=existing_user_message.created_at,
        )

        if has_later_messages:
            raise ConflictError(
                "Cannot retry an earlier incomplete message"
            )

    guided_instructions = None

    if conversation.mode == AiConversationMode.GUIDED:
        if conversation.assignment_id is None:
            raise ConflictError(
                "Guided conversation has no psychologist assignment"
            )

        assignment = await get_assignment_by_id(
            db=db,
            assignment_id=conversation.assignment_id,
            for_update=True,
        )

        if assignment is None:
            raise ConflictError(
                "Guided conversation is no longer available"
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
            raise ConflictError(
                "Guided conversation is no longer available"
            )

        care_plan = await get_ai_care_plan_by_assignment_id(
            session=db,
            assignment_id=conversation.assignment_id,
        )

        if care_plan is None:
            raise ConflictError(
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
            raise ConflictError(
                "Guided conversation is currently unavailable"
            )

        active_version = await get_ai_care_plan_version(
            session=db,
            care_plan_id=care_plan.id,
            version_id=latest_care_plan_event.version_id,
        )

        if active_version is None:
            raise NotFoundError(
                "Active care plan version not found"
            )

        guided_instructions = (
            active_version.instructions_for_ai
        )

    if existing_user_message is not None:
        user_message = existing_user_message
    else:
        user_message = await create_ai_message(
            session=db,
            conversation_id=conversation.id,
            role=AiMessageRole.USER,
            content=normalized_content,
            request_id=request_id,
        )

    message_history = await get_recent_ai_messages_for_conversation(
        session=db,
        conversation_id=conversation.id,
        limit=settings.OPENAI_HISTORY_MESSAGE_LIMIT,
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

    try:
        assistant_content = await generate_ai_reply(
            messages=provider_messages,
            guided_instructions=guided_instructions,
        )
    except AiProviderError:
        await db.commit()
        await db.refresh(user_message)
        raise

    assistant_message = await create_ai_message(
        session=db,
        conversation_id=conversation.id,
        role=AiMessageRole.ASSISTANT,
        content=assistant_content,
        request_id=request_id,
    )

    await db.commit()

    await db.refresh(user_message)
    await db.refresh(assistant_message)

    return {
        "user_message": user_message,
        "assistant_message": assistant_message,
    }