import uuid
from datetime import datetime

from pydantic import BaseModel, Field


class PatientAssignmentRequestCreate(BaseModel):
    psychologist_id: uuid.UUID
    comment: str = Field(
    min_length=20,
    max_length=2000,
)


class PatientAssignmentReject(BaseModel):
    comment: str


class PatientAssignmentFinish(BaseModel):
    comment: str


class PatientAssignmentOut(BaseModel):
    id: uuid.UUID
    patient_id: uuid.UUID
    psychologist_id: uuid.UUID

    model_config = {
        "from_attributes": True,
    }


class PatientAssignmentEventOut(BaseModel):
    id: uuid.UUID
    assignment_id: uuid.UUID
    event_type: str
    performed_by_id: uuid.UUID | None
    comment: str | None
    created_at: datetime

    model_config = {
        "from_attributes": True,
    }

class PatientAssignmentWithLatestEventOut(BaseModel):
    id: uuid.UUID
    patient_id: uuid.UUID
    psychologist_id: uuid.UUID
    latest_event: PatientAssignmentEventOut

    model_config = {
        "from_attributes": True,
    }