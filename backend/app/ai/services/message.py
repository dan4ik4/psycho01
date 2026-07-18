import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from app.ai.crud.conversation import get_ai_conversation_for_patient
from app.ai.crud.message import create_ai_message
from app.ai.models.message import AiMessage, AiMessageRole


async def send_user_message(
    db: AsyncSession,
    conversation_id: uuid.UUID,
    patient_id: uuid.UUID,
    content: str,
) -> AiMessage:
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

    message = await create_ai_message(
        session=db,
        conversation_id=conversation.id,
        role=AiMessageRole.USER,
        content=normalized_content,
    )

    await db.commit()
    await db.refresh(message)

    return message