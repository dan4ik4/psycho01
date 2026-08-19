import uuid
from datetime import date

from fastapi_users import schemas
from pydantic import BaseModel, EmailStr, Field


class UserRead(schemas.BaseUser[uuid.UUID]):
    first_name: str | None = None
    last_name: str | None = None
    birth_date: date | None = None

    is_psychologist: bool = False

    specialization: str | None = None
    license_number: str | None = None
    bio: str | None = None
    experience_years: int | None = None


class UserCreate(schemas.BaseUserCreate):
    email: EmailStr
    password: str

    first_name: str | None = Field(
        default=None,
        max_length=100,
    )

    last_name: str | None = Field(
        default=None,
        max_length=100,
    )

    birth_date: date | None = None


class UserUpdate(BaseModel):
    first_name: str | None = Field(
        default=None,
        max_length=100,
    )

    last_name: str | None = Field(
        default=None,
        max_length=100,
    )

    birth_date: date | None = None


class PsychologistUpdate(BaseModel):
    specialization: str | None = Field(
        default=None,
        max_length=150,
    )

    license_number: str | None = Field(
        default=None,
        max_length=100,
    )

    bio: str | None = None

    experience_years: int | None = Field(
        default=None,
        ge=0,
    )