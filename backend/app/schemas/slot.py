import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict


class SlotCreate(BaseModel):
    start_at: datetime
    end_at: datetime


class SlotOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    psychologist_id: uuid.UUID
    start_at: datetime
    end_at: datetime
    is_booked: bool
    created_at: datetime