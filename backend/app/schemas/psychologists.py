import uuid

from pydantic import BaseModel, ConfigDict, Field


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
    avatar_url: str | None = None
    hourly_net_minor: int | None = Field(
        default=None,
        description="Psychologist net hourly rate in minor currency units (USD cents), not the final client price",
    )
    currency: str
    hourly_price_minor: int | None = Field(
        default=None,
        description="Estimated total client price for 60 minutes, including configured fees. Use slot quote for final session price.",
    )
