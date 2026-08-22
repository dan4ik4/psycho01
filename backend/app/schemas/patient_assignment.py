import uuid
from datetime import datetime

from typing import Annotated

from pydantic import BaseModel, StringConstraints


AssignmentRequestComment = Annotated[
    str,
    StringConstraints(
        strip_whitespace=True,
        min_length=20,
        max_length=2000,
    ),
]

RequiredAssignmentComment = Annotated[
    str,
    StringConstraints(
        strip_whitespace=True,
        min_length=1,
        max_length=2000,
    ),
]


class PatientAssignmentRequestCreate(BaseModel):
    psychologist_id: uuid.UUID
    comment: AssignmentRequestComment


class PatientAssignmentReject(BaseModel):
    comment: RequiredAssignmentComment


class PatientAssignmentFinish(BaseModel):
    comment: RequiredAssignmentComment


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