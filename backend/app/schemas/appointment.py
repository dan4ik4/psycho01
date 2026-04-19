import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict

from app.models.appointment import AppointmentStatus, MissedBy


class AvailableSlotOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    psychologist_id: uuid.UUID
    start_at: datetime
    end_at: datetime

class AppointmentBookIn(BaseModel):
    slot_id: uuid.UUID

class AppointmentOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    slot_id: uuid.UUID
    psychologist_id: uuid.UUID
    patient_id: uuid.UUID
    status: AppointmentStatus
    missed_by: Optional[MissedBy] = None
    start_at: datetime
    end_at: datetime