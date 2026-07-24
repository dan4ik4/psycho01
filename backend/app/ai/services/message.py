import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from app.ai.crud.conversation import get_ai_conversation_for_patient
from app.ai.crud.message import (
    create_ai_message,
    get_ai_messages_for_conversation,
)
from app.ai.models.message import AiMessage, AiMessageRole
from app.ai.providers.chat import ChatMessage, generate_ai_reply


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