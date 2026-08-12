import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.ai.models.conversation import AiConversation, AiConversationMode


async def create_ai_conversation(
    session: AsyncSession,
    patient_id: uuid.UUID,
    name: str,
    mode: AiConversationMode,
    assignment_id: uuid.UUID | None = None,
) -> AiConversation:
    conversation = AiConversation(
        patient_id=patient_id,
        assignment_id=assignment_id,
        name=name,
        mode=mode,
    )

    session.add(conversation)
    await session.flush()

    return conversation

async def get_ai_conversation_for_patient(
    session: AsyncSession,
    conversation_id: uuid.UUID,
    patient_id: uuid.UUID,
    *,
    for_update: bool = False,
) -> AiConversation | None:
    stmt = select(AiConversation).where(
        AiConversation.id == conversation_id,
        AiConversation.patient_id == patient_id,
    )

    if for_update:
        stmt = stmt.with_for_update()

    result = await session.execute(stmt)
    return result.scalar_one_or_none()

async def get_ai_conversations_for_patient(
    session: AsyncSession,
    patient_id: uuid.UUID,
) -> list[AiConversation]:
    stmt = (
        select(AiConversation)
        .where(AiConversation.patient_id == patient_id)
        .order_by(AiConversation.created_at.desc())
    )

    result = await session.execute(stmt)
    return list(result.scalars().all())

async def rename_ai_conversation(
    session: AsyncSession,
    conversation: AiConversation,
    name: str,
) -> AiConversation:
    conversation.name = name

    await session.flush()

    return conversation

async def get_ai_conversation_with_messages_for_patient(
    session: AsyncSession,
    conversation_id: uuid.UUID,
    patient_id: uuid.UUID,
) -> AiConversation | None:
    stmt = (
        select(AiConversation)
        .options(
            selectinload(AiConversation.messages),
        )
        .where(
            AiConversation.id == conversation_id,
            AiConversation.patient_id == patient_id,
        )
    )

    result = await session.execute(stmt)
    return result.scalar_one_or_none()

