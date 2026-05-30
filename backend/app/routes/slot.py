import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import get_db
from app.models.user import User
from app.auth.deps import current_active_user
from app.schemas.slot import SlotCreate, SlotOut, SlotWithLatestEventOut
from app.services.slot import (
    create_slot,
    get_my_slots,
    remove_slot,
    get_available_slots,
    book_slot,
    cancel_slot_booking,
    get_my_booked_slots,
    get_slot_history,
)
from app.schemas.slot import SlotAction

router = APIRouter(
    prefix="/slots",
    tags=["slots"],
)

def build_slot_with_event_response(slot, latest_event):
    return SlotWithLatestEventOut(
        id=slot.id,
        psychologist_id=slot.psychologist_id,
        start_at=slot.start_at,
        end_at=slot.end_at,
        latest_event=latest_event,
    )


@router.post("/create", response_model=SlotOut)
async def create_slot_endpoint(
    data: SlotCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
):
    try:
        slot = await create_slot(
            db=db,
            user=user,
            start_at=data.start_at,
            end_at=data.end_at,
        )

        return slot

    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e),
        )
    

@router.get("/my", response_model=list[SlotOut])
async def get_my_slots_endpoint(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
):
    try:
        return await get_my_slots(
            db=db,
            user=user,
        )

    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e),
        )
    

@router.post("/{slot_id}/remove", response_model=SlotOut)
async def remove_slot_endpoint(
    slot_id: uuid.UUID,
    data: SlotAction,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
):
    try:
        slot = await remove_slot(
            db=db,
            slot_id=slot_id,
            user=user,
            comment=data.comment,
        )

        return slot

    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e),
        )
    
@router.get("/available", response_model=list[SlotOut])
async def get_available_slots_endpoint(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
):
    try:
        return await get_available_slots(
            db=db,
            user=user,
        )

    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e),
        )


@router.post("/{slot_id}/book", response_model=SlotOut)
async def book_slot_endpoint(
    slot_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
):
    try:
        return await book_slot(
            db=db,
            slot_id=slot_id,
            user=user,
        )

    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e),
        )


@router.post("/{slot_id}/cancel", response_model=SlotOut)
async def cancel_slot_booking_endpoint(
    slot_id: uuid.UUID,
    data: SlotAction,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
):
    try:
        return await cancel_slot_booking(
            db=db,
            slot_id=slot_id,
            user=user,
            comment=data.comment,
        )

    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e),
        )
    

@router.get("/booked", response_model=list[SlotWithLatestEventOut])
async def get_my_booked_slots_endpoint(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
):
    try:
        slots = await get_my_booked_slots(
            db=db,
            user=user,
        )

        return [
            build_slot_with_event_response(slot, latest_event)
            for slot, latest_event in slots
        ]

    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e),
        )
    
@router.get("/history", response_model=list[SlotWithLatestEventOut])
async def get_slot_history_endpoint(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
):
    try:
        slots = await get_slot_history(
            db=db,
            user=user,
        )

        return [
            build_slot_with_event_response(slot, latest_event)
            for slot, latest_event in slots
        ]

    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e),
        )
    
