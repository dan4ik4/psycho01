import uuid
from datetime import datetime

from pydantic import BaseModel, field_validator, Field
from app.models.slot_event import SlotEventType


class SlotCreate(BaseModel):
    start_at: datetime
    end_at: datetime

    @field_validator("start_at", "end_at")
    @classmethod
    def datetime_must_have_timezone(cls, value: datetime):
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("Datetime must include timezone")

        return value

    @field_validator("end_at")
    @classmethod
    def end_after_start(cls, end_at: datetime, info):
        start_at = info.data.get("start_at")

        if start_at and end_at <= start_at:
            raise ValueError("end_at must be after start_at")

        return end_at


class SlotOut(BaseModel):
    id: uuid.UUID
    psychologist_id: uuid.UUID
    start_at: datetime
    end_at: datetime

    model_config = {
        "from_attributes": True,
    }

class SlotAction(BaseModel):
    comment: str | None = Field(
        default=None,
        max_length=2000,
    )

    @field_validator("comment")
    @classmethod
    def normalize_comment(
        cls,
        value: str | None,
    ) -> str | None:
        if value is None:
            return None

        normalized_comment = value.strip()

        return normalized_comment or None
    
class SlotEventOut(BaseModel):
    id: uuid.UUID
    event_type: SlotEventType
    patient_id: uuid.UUID | None
    performed_by_id: uuid.UUID | None
    comment: str | None
    created_at: datetime

    class Config:
        from_attributes = True

class SlotWithLatestEventOut(BaseModel):
    id: uuid.UUID
    psychologist_id: uuid.UUID
    start_at: datetime
    end_at: datetime
    latest_event: SlotEventOut | None

    class Config:
        from_attributes = True

