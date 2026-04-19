from pydantic import BaseModel


class AgoraTokenResponse(BaseModel):
    channel_name: str
    token: str
    uid: int