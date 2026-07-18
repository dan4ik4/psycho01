import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.ai.models.message import AiMessage, AiMessageRole


async def create_ai_message(
    session: AsyncSession,
    conversation_id: uuid.UUID,
    role: AiMessageRole,
    content: str,
) -> AiMessage:
    message = AiMessage(
        conversation_id=conversation_id,
        role=role,
        content=content,
    )

    session.add(message)
    await session.flush()

    return message


async def get_ai_messages_for_conversation(
    session: AsyncSession,
    conversation_id: uuid.UUID,
) -> list[AiMessage]:
    stmt = (
        select(AiMessage)
        .where(AiMessage.conversation_id == conversation_id)
        .order_by(AiMessage.created_at.asc())
    )

    result = await session.execute(stmt)
    return list(result.scalars().all())