from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
import uuid

from app.ai.schemas.conversation import (
    AiConversationCreate,
    AiConversationOut,
    AiConversationDetailOut,
    AiConversationRename,
)
from app.ai.services.conversation import (
    create_conversation,
    get_my_conversations,
    get_conversation_with_messages,
    rename_conversation,
)
from app.auth.deps import current_active_user
from app.db.deps import get_db
from app.models.user import User


router = APIRouter(
    prefix="/conversations",
    tags=["AI conversations"],
)


@router.post(
    "",
    response_model=AiConversationOut,
    status_code=status.HTTP_201_CREATED,
)
async def create_ai_conversation_endpoint(
    data: AiConversationCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
) -> AiConversationOut:
    try:
        return await create_conversation(
            db=db,
            user=user,
            name=data.name,
            mode=data.mode,
        )

    except ValueError as error:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(error),
        ) from error
    
@router.get(
    "",
    response_model=list[AiConversationOut],
)
async def get_my_ai_conversations_endpoint(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
) -> list[AiConversationOut]:
    try:
        return await get_my_conversations(
            db=db,
            user=user,
        )

    except ValueError as error:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(error),
        ) from error


@router.patch(
    "/{conversation_id}",
    response_model=AiConversationOut,
)
async def rename_ai_conversation_endpoint(
    conversation_id: uuid.UUID,
    data: AiConversationRename,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
) -> AiConversationOut:
    try:
        return await rename_conversation(
            db=db,
            user=user,
            conversation_id=conversation_id,
            name=data.name,
        )

    except ValueError as error:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(error),
        ) from error
    
@router.get(
    "/{conversation_id}",
    response_model=AiConversationDetailOut,
)
async def get_ai_conversation_endpoint(
    conversation_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
) -> AiConversationDetailOut:
    try:
        return await get_conversation_with_messages(
            db=db,
            user=user,
            conversation_id=conversation_id,
        )

    except ValueError as error:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(error),
        ) from error
    
