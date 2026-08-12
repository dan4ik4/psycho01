import uuid

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import current_active_user, get_db
from app.models.user import User
from app.schemas.call import CallJoinOut
from app.services.call import join_call, leave_call


router = APIRouter(
    prefix="/calls",
    tags=["Calls"],
)


@router.post(
    "/{slot_id}/join",
    response_model=CallJoinOut,
)
async def join_call_route(
    slot_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
):
    return await join_call(
        db=db,
        slot_id=slot_id,
        user=user,
    )


@router.post(
    "/{slot_id}/leave",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def leave_call_route(
    slot_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
):
    await leave_call(
        db=db,
        slot_id=slot_id,
        user=user,
    )