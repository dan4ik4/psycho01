import uuid
from datetime import datetime

from pydantic import BaseModel, Field

from app.ai.models.message import AiMessageRole


class AiMessageCreate(BaseModel):
    content: str = Field(
        min_length=1,
        max_length=10000,
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