import uuid

from pydantic import BaseModel

from app.models.call import CallProvider


class CallJoinOut(BaseModel):
    call_id: uuid.UUID
    slot_id: uuid.UUID
    provider: CallProvider
    room_id: str
    uid: int
    token: str
    app_id: str