import uuid
from datetime import datetime

from pydantic import BaseModel, Field

from app.ai.models.conversation import AiConversationMode
from app.ai.schemas.message import AiMessageOut

class AiConversationRename(BaseModel):
    name: str = Field(
        min_length=1,
        max_length=100,
    )

class AiConversationCreate(BaseModel):
    mode: AiConversationMode
    name: str | None = Field(
        default=None,
        max_length=100,
    )

class AiConversationOut(BaseModel):
    id: uuid.UUID
    patient_id: uuid.UUID
    assignment_id: uuid.UUID | None
    name: str
    mode: AiConversationMode
    created_at: datetime

    model_config = {
        "from_attributes": True,
    }

class AiConversationDetailOut(AiConversationOut):
    messages: list[AiMessageOut]