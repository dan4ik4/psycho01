import uuid
from datetime import datetime

from sqlalchemy import and_, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.ai.models.message import AiMessage, AiMessageRole


async def create_ai_message(
    session: AsyncSession,
    conversation_id: uuid.UUID,
    role: AiMessageRole,
    content: str,
    request_id: uuid.UUID | None = None,
) -> AiMessage:
    message = AiMessage(
        conversation_id=conversation_id,
        role=role,
        content=content,
        request_id=request_id,
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
        .order_by(
            AiMessage.created_at.asc(),
            AiMessage.id.asc(),
        )
    )

    result = await session.execute(stmt)
    return list(result.scalars().all())

async def get_ai_message_by_request_id(
    session: AsyncSession,
    conversation_id: uuid.UUID,
    request_id: uuid.UUID,
    role: AiMessageRole,
) -> AiMessage | None:
    stmt = select(AiMessage).where(
        AiMessage.conversation_id == conversation_id,
        AiMessage.request_id == request_id,
        AiMessage.role == role,
    )

    result = await session.execute(stmt)
    return result.scalar_one_or_none()

async def get_recent_ai_messages_for_conversation(
    session: AsyncSession,
    conversation_id: uuid.UUID,
    limit: int,
) -> list[AiMessage]:
    stmt = (
        select(AiMessage)
        .where(
            AiMessage.conversation_id == conversation_id,
        )
        .order_by(
            AiMessage.created_at.desc(),
            AiMessage.id.desc(),
        )
        .limit(limit)
    )

    result = await session.execute(stmt)

    messages = list(result.scalars().all())
    messages.reverse()

    return messages

async def has_ai_messages_after(
    session: AsyncSession,
    conversation_id: uuid.UUID,
    message_id: uuid.UUID,
    created_at: datetime,
) -> bool:
    stmt = (
        select(AiMessage.id)
        .where(
            AiMessage.conversation_id == conversation_id,
            or_(
                AiMessage.created_at > created_at,
                and_(
                    AiMessage.created_at == created_at,
                    AiMessage.id > message_id,
                ),
            ),
        )
        .limit(1)
    )

    result = await session.execute(stmt)

    return result.scalar_one_or_none() is not None

