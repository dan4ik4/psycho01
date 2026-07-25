import uuid

from pydantic import BaseModel, ConfigDict


class PsychologistListOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    first_name: str | None = None
    last_name: str | None = None
    specialization: str | None = None
    bio: str | None = None
    experience_years: int | None = None
    average_rating: float | None = None
    ratings_count: int = 0