from fastapi import APIRouter

from app.ai.routes.conversation import router as conversation_router
from .message import router as message_router


api = APIRouter(prefix="/api/v1/ai")

#conversation
api.include_router(conversation_router)

#messages
api.include_router(message_router)