from fastapi import APIRouter

from app.ai.routes.conversation import router as conversation_router
from .message import router as message_router
from .ai_care_plan import router as ai_care_plan_router


api = APIRouter(prefix="/api/v1/ai")

#conversation
api.include_router(conversation_router)

#messages
api.include_router(message_router)

#ai care plan
api.include_router(ai_care_plan_router)