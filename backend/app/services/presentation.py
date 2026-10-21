"""Enrich already-authorized records. No public patient lookup is exposed."""

from app.billing.models import Booking, now
from app.models.user import User
from app.schemas.patient_assignment import PatientAssignmentWithLatestEventOut
from app.schemas.slot import SlotWithLatestEventOut
from app.schemas.user import PatientSummary
from sqlalchemy import select


async def patient_summaries(db, ids):
    if not ids:
        return {}
    users = (await db.scalars(select(User).where(User.id.in_(ids)))).all()
    return {user.id: PatientSummary.model_validate(user) for user in users}


async def assignment_views(db, rows):
    patients = await patient_summaries(
        db, {assignment.patient_id for assignment, _ in rows}
    )
    return [
        PatientAssignmentWithLatestEventOut(
            id=assignment.id,
            patient_id=assignment.patient_id,
            psychologist_id=assignment.psychologist_id,
            latest_event=event,
            patient=patients.get(assignment.patient_id),
        )
        for assignment, event in rows
    ]


async def slot_views(db, rows, *, reservations=False):
    held = {}
    if reservations and rows:
        bookings = (
            await db.scalars(
                select(Booking).where(
                    Booking.slot_id.in_([slot.id for slot, _ in rows]),
                    Booking.status == "pending",
                    Booking.hold_until > now(),
                )
            )
        ).all()
        held = {booking.slot_id: booking for booking in bookings}
    visible_ids = {
        event.patient_id
        for _, event in rows
        if event
        and event.event_type.value in ("booked", "completed", "missed")
        and event.patient_id
    }
    visible_ids.update(booking.patient_id for booking in held.values())
    patients = await patient_summaries(db, visible_ids)
    result = []
    for slot, event in rows:
        state = event.event_type.value if event else "free"
        patient_id = (
            event.patient_id
            if event and state in ("booked", "completed", "missed")
            else None
        )
        if reservations and state in ("created", "cancelled", "free"):
            state = "free"
            if slot.id in held:
                state, patient_id = "reserved", held[slot.id].patient_id
        elif state == "created":
            state = "free"
        result.append(
            SlotWithLatestEventOut(
                id=slot.id,
                psychologist_id=slot.psychologist_id,
                start_at=slot.start_at,
                end_at=slot.end_at,
                latest_event=event,
                status=state,
                patient=patients.get(patient_id),
            )
        )
    return result
