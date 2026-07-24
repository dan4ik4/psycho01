import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.ai.schemas.message import AiMessageCreate, AiMessageExchangeOut
from app.ai.services.message import send_user_message
from app.auth.deps import current_active_user
from app.db.deps import get_db
from app.models.user import User
from app.ai.providers.chat import AiProviderError


router = APIRouter(
    prefix="/conversations",
    tags=["AI messages"],
)


@router.post(
    "/{conversation_id}/messages",
    response_model=AiMessageExchangeOut,
    status_code=status.HTTP_201_CREATED,
)
async def send_ai_message_endpoint(
    conversation_id: uuid.UUID,
    data: AiMessageCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
) -> AiMessageExchangeOut:
    try:
        return await send_user_message(
            db=db,
            conversation_id=conversation_id,
            patient_id=user.id,
            content=data.content,
        )

    except ValueError as error:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(error),
        ) from error

    except AiProviderError as error:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=str(error),
        ) from error