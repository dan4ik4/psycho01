from __future__ import annotations

import uuid
from pydantic import BaseModel


class PsychologistListItem(BaseModel):
    id: uuid.UUID
    email: str | None = None

    specialization: str | None = None
    experience_years: int | None = None #может номенр лицензии не выдавать пациентам??
    license_number: str | None = None
    price_per_hour: int | None = None
    bio: str | None = None

    class Config:
        from_attributes = True