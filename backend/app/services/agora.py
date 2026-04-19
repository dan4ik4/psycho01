import time
import uuid
from datetime import datetime

from agora_token_builder import RtcTokenBuilder
from app.core.settings import settings

def generate_agora_uid(user_id: uuid.UUID) -> int:
    return user_id.int % (2**31 - 1)

def generate_agora_channel_name(appointment_id: str) -> str:
    return f"appointment_{appointment_id}"


def datetime_to_timestamp(value: datetime) -> int:
    return int(value.timestamp())


def generate_agora_token(channel_name: str, uid: int, expire_timestamp: int) -> str:
    token = RtcTokenBuilder.buildTokenWithUid(
        settings.AGORA_APP_ID,
        settings.AGORA_APP_CERTIFICATE,
        channel_name,
        uid,
        1,
        expire_timestamp,
    )
    return token