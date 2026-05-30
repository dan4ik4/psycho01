import uuid
from datetime import datetime

from pydantic import BaseModel, Field


class PsychologistRatingUpsert(BaseModel):
    rating: int = Field(ge=1, le=5)
    comment: str | None = None


class PsychologistRatingOut(BaseModel):
    id: uuid.UUID
    patient_id: uuid.UUID
    psychologist_id: uuid.UUID
    rating: int
    comment: str | None
    created_at: datetime
    updated_at: datetime


class PsychologistRatingSummary(BaseModel):
    psychologist_id: uuid.UUID
    average_rating: float | None
    ratings_count: int