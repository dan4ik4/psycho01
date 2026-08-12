import uuid
from datetime import datetime

from pydantic import BaseModel, Field

from app.ai.models.message import AiMessageRole
from app.core.settings import settings


class AiMessageCreate(BaseModel):
    request_id: uuid.UUID

    content: str = Field(
        min_length=1,
        max_length=settings.OPENAI_MESSAGE_MAX_LENGTH,
    )


class AiMessageOut(BaseModel):
    id: uuid.UUID
    conversation_id: uuid.UUID
    role: AiMessageRole
    content: str
    created_at: datetime

    model_config = {
        "from_attributes": True,
    }

class AiMessageExchangeOut(BaseModel):
    user_message: AiMessageOut
    assistant_message: AiMessageOut