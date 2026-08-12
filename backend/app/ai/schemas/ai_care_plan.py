from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.ai.models.ai_care_plan import AiCarePlanEventType


class AiCarePlanContentBase(BaseModel):
    instructions_for_ai: str = Field(
        max_length=10000,
    )
    patient_recommendations: str | None = None

    @field_validator("instructions_for_ai")
    @classmethod
    def validate_instructions_for_ai(cls, value: str) -> str:
        value = value.strip()

        if not value:
            raise ValueError("Instructions for AI cannot be empty")

        return value

    @field_validator("patient_recommendations")
    @classmethod
    def validate_patient_recommendations(
        cls,
        value: str | None,
    ) -> str | None:
        if value is None:
            return None

        value = value.strip()

        return value or None


class AiCarePlanCreate(AiCarePlanContentBase):
    assignment_id: UUID


class AiCarePlanVersionCreate(AiCarePlanContentBase):
    pass


class AiCarePlanActivate(BaseModel):
    version_id: UUID
    comment: str | None = None


class AiCarePlanStateChange(BaseModel):
    comment: str | None = None


class AiCarePlanRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    assignment_id: UUID
    created_by_id: UUID
    created_at: datetime


class AiCarePlanVersionRead(AiCarePlanContentBase):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    care_plan_id: UUID
    version: int
    created_by_id: UUID
    created_at: datetime


class AiCarePlanEventRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    care_plan_id: UUID
    version_id: UUID
    event_type: AiCarePlanEventType
    performed_by_id: UUID
    comment: str | None
    created_at: datetime

class AiCarePlanPatientRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    care_plan_id: UUID
    version_id: UUID
    patient_recommendations: str | None
    event_type: AiCarePlanEventType

class AiCarePlanPsychologistRead(BaseModel):
    care_plan: AiCarePlanRead
    latest_version: AiCarePlanVersionRead
    latest_event: AiCarePlanEventRead | None