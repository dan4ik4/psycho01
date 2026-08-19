from agora_token_builder import RtcTokenBuilder
from app.core.settings import settings

def generate_agora_channel_name(call_id: str) -> str:
    return f"call_{call_id}"

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