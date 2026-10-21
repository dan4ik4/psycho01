import uuid

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import current_active_user, get_db
from app.models.user import User
from app.schemas.slot import SlotAction, SlotCreate, SlotOut, SlotWithLatestEventOut
from app.services.presentation import slot_views
from app.services.slot import (
    book_slot,
    cancel_slot_booking,
    create_slot,
    get_available_slots,
    get_my_booked_slots,
    get_my_slots,
    get_slot_history,
    remove_slot,
)


class BookingRequest(BaseModel):
    request_id: uuid.UUID


router = APIRouter(
    prefix="/slots",
    tags=["slots"],
)


@router.post(
    "/create",
    response_model=SlotOut,
    description="Psychologist only. ISO 8601 timestamps must include Z or an offset; start in future, duration at least 15 minutes, no overlap. Invalid datetime fields: 422; past/short slots: 400; overlaps: 409.",
)
async def create_slot_endpoint(
    data: SlotCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
):
    return await create_slot(
        db=db,
        user=user,
        start_at=data.start_at,
        end_at=data.end_at,
    )


@router.get(
    "/my",
    response_model=list[SlotWithLatestEventOut],
    description="Psychologist only. Future/non-ended slots with booking state and minimal patient identity. Removed slots are excluded; pending payment holds are reserved.",
)
async def get_my_slots_endpoint(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
):
    slots = await get_my_slots(db=db, user=user)
    from app.crud.slot import get_slots_with_latest_events

    visible_ids = {slot.id for slot in slots}
    rows = await get_slots_with_latest_events(db, psychologist_id=user.id)
    return await slot_views(
        db,
        [(slot, event) for slot, event in rows if slot.id in visible_ids],
        reservations=True,
    )


@router.post("/{slot_id}/remove", response_model=SlotOut)
async def remove_slot_endpoint(
    slot_id: uuid.UUID,
    data: SlotAction,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
):
    return await remove_slot(
        db=db,
        slot_id=slot_id,
        user=user,
        comment=data.comment,
    )


@router.get("/available", response_model=list[SlotOut])
async def get_available_slots_endpoint(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
):
    return await get_available_slots(
        db=db,
        user=user,
    )


@router.post("/{slot_id}/book")
async def book_slot_endpoint(
    slot_id: uuid.UUID,
    data: BookingRequest,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
):
    from app.billing.service import booking_view

    booking = await book_slot(
        db=db, slot_id=slot_id, user=user, request_id=data.request_id
    )
    return await booking_view(db, booking)


@router.post("/{slot_id}/cancel", response_model=SlotOut)
async def cancel_slot_booking_endpoint(
    slot_id: uuid.UUID,
    data: SlotAction,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
):
    return await cancel_slot_booking(
        db=db,
        slot_id=slot_id,
        user=user,
        comment=data.comment,
    )


@router.get(
    "/booked",
    response_model=list[SlotWithLatestEventOut],
    description="Patient only. Own confirmed bookings; psychologists must use /slots/my.",
)
async def get_my_booked_slots_endpoint(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
):
    slots = await get_my_booked_slots(
        db=db,
        user=user,
    )

    return await slot_views(db, slots)


@router.get(
    "/history",
    response_model=list[SlotWithLatestEventOut],
)
async def get_slot_history_endpoint(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
):
    slots = await get_slot_history(
        db=db,
        user=user,
    )

    return await slot_views(db, slots)
