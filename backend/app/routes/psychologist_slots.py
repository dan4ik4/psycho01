import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import current_active_user
from app.crud.slot import create_slot, delete_slot, get_psychologist_slots, get_slot_by_id
from app.db.deps import get_db
from app.models.user import User, UserRole
from app.schemas.slot import SlotCreate, SlotOut

router = APIRouter(prefix="/psychologist/slots", tags=["psychologist-slots"])


@router.post("", response_model=SlotOut, status_code=status.HTTP_201_CREATED)
async def create_psychologist_slot(
    data: SlotCreate,
    session: AsyncSession = Depends(get_db),
    current_user: User = Depends(current_active_user),
) -> SlotOut:
    if current_user.role != UserRole.psychologist:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only psychologists can create slots.",
        )

    if data.end_at <= data.start_at:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="end_at must be greater than start_at.",
        )

    now = datetime.now(timezone.utc)
    if data.start_at <= now:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Slot start time must be in the future.",
        )

    try:
        slot = await create_slot(
            session=session,
            psychologist_id=current_user.id,
            start_at=data.start_at,
            end_at=data.end_at,
        )
    except IntegrityError:
        await session.rollback()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This slot overlaps with an existing slot.",
        )

    return slot


@router.get("", response_model=list[SlotOut])
async def get_my_slots(
    session: AsyncSession = Depends(get_db),
    current_user: User = Depends(current_active_user),
) -> list[SlotOut]:
    if current_user.role != UserRole.psychologist:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only psychologists can view their slots.",
        )

    return await get_psychologist_slots(session=session, psychologist_id=current_user.id)


@router.delete("/{slot_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_my_slot(
    slot_id: uuid.UUID,
    session: AsyncSession = Depends(get_db),
    current_user: User = Depends(current_active_user),
) -> Response:
    if current_user.role != UserRole.psychologist:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only psychologists can delete slots.",
        )

    slot = await get_slot_by_id(session=session, slot_id=slot_id)
    if slot is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Slot not found.",
        )

    if slot.psychologist_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You can delete only your own slots.",
        )

    if slot.is_booked:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Booked slot cannot be deleted.",
        )

    await delete_slot(session=session, slot=slot)
    return Response(status_code=status.HTTP_204_NO_CONTENT)