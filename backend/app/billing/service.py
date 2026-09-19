"""Booking and financial state transitions. Locks: assignment -> slot -> booking -> payment."""

from datetime import timedelta

from sqlalchemy import select

from app.billing.errors import BillingError
from app.billing.models import (
    Booking,
    Earning,
    MoneyOperation,
    Payment,
    PsychologistBilling,
    now,
)
from app.billing.pricing import quote_slot
from app.billing.providers import payment_provider
from app.core.errors import ConflictError, ForbiddenError, NotFoundError
from app.core.settings import settings
from app.crud.patient_assignment import (
    get_assignment_by_id,
    get_latest_assignment_event,
    get_latest_patient_assignment,
)
from app.crud.slot import create_slot_event, get_latest_slot_event, get_slot_by_id
from app.models.patient_assignment_event import PatientAssignmentEventType
from app.models.slot_event import SlotEventType
from app.models.user import User


async def active_booking(db, slot_id):
    return await db.scalar(
        select(Booking).where(
            Booking.slot_id == slot_id, Booking.status.in_(["pending", "confirmed"])
        )
    )


async def reserve_booking(db, slot_id, user, request_id):
    if user.is_psychologist:
        raise ForbiddenError("Only patients can book consultations")
    # Serialize duplicate keys across slots without touching financial rows first.
    from sqlalchemy import text

    await db.execute(
        text("SELECT pg_advisory_xact_lock(hashtextextended(:k, 0))"),
        {"k": f"reserve:{user.id}:{request_id}"},
    )
    previous = await db.scalar(
        select(Booking).where(
            Booking.patient_id == user.id, Booking.request_id == request_id
        )
    )
    if previous:
        if previous.slot_id != slot_id or previous.test_mode != settings.TEST_MODE:
            raise ConflictError("Request id already used for another booking")
        return previous
    assignment_data = await get_latest_patient_assignment(db, user.id)
    if not assignment_data:
        raise ConflictError("Patient has no active assignment")
    assignment = await get_assignment_by_id(db, assignment_data[0].id, for_update=True)
    latest_assignment = await get_latest_assignment_event(db, assignment.id)
    if (
        not latest_assignment
        or latest_assignment.event_type != PatientAssignmentEventType.ACCEPTED
    ):
        raise ConflictError("Patient has no active assignment")
    slot = await get_slot_by_id(db, slot_id, for_update=True)
    if not slot:
        raise NotFoundError("Slot not found")
    if slot.psychologist_id != assignment.psychologist_id or slot.start_at <= now():
        raise ConflictError("Slot is not available to this patient")
    psychologist = await db.get(User, slot.psychologist_id)
    if not psychologist.is_active or not psychologist.is_psychologist:
        raise ConflictError("Psychologist is unavailable")
    latest = await get_latest_slot_event(db, slot.id)
    if not latest or latest.event_type not in (
        SlotEventType.CREATED,
        SlotEventType.CANCELLED,
    ):
        raise ConflictError("Slot is not available")
    active = await active_booking(db, slot.id)
    if active:
        if active.status == "pending" and active.hold_until <= now():
            active.status = "expired"
            await db.flush()
        else:
            raise ConflictError("Slot is already reserved")
    quote = await quote_slot(db, slot)
    profile = await db.get(PsychologistBilling, slot.psychologist_id)
    if not settings.TEST_MODE:
        if not settings.BILLING_LIVE_ENABLED:
            raise BillingError(
                "live_billing_disabled", "Live billing is not enabled", status_code=503
            )
        if (
            not profile.stripe_account_id
            or not profile.charges_enabled
            or not profile.payouts_enabled
        ):
            raise BillingError(
                "psychologist_not_connected",
                "Psychologist payment account is not ready",
            )
    booking = Booking(
        slot_id=slot.id,
        patient_id=user.id,
        psychologist_id=slot.psychologist_id,
        assignment_id=assignment.id,
        request_id=request_id,
        test_mode=settings.TEST_MODE,
        quote=quote,
        hold_until=min(
            slot.start_at, now() + timedelta(minutes=settings.BOOKING_HOLD_MINUTES)
        ),
    )
    db.add(booking)
    await db.flush()
    db.add(
        Payment(
            booking_id=booking.id,
            provider="mock" if settings.TEST_MODE else "stripe",
            amount_minor=quote["amount_minor"],
            currency=quote["currency"],
            destination=profile.stripe_account_id,
        )
    )
    await db.commit()
    return booking


async def owned_booking(db, booking_id, user):
    booking = await db.get(Booking, booking_id)
    if (
        not booking
        or booking.test_mode != settings.TEST_MODE
        or user.id not in (booking.patient_id, booking.psychologist_id)
        and not user.is_superuser
    ):
        raise NotFoundError("Booking not found")
    return booking


async def booking_view(db, booking):
    payment = await db.scalar(select(Payment).where(Payment.booking_id == booking.id))
    return dict(
        id=booking.id,
        slot_id=booking.slot_id,
        status=booking.status,
        test_mode=booking.test_mode,
        hold_until=booking.hold_until,
        quote=booking.quote,
        outcome=booking.outcome,
        payment_id=payment.id if payment else None,
        payment_status=payment.status if payment else "legacy",
        checkout_url=payment.checkout_url if payment else None,
    )


async def checkout(db, booking_id, user):
    booking = await owned_booking(db, booking_id, user)
    if booking.patient_id != user.id:
        raise ForbiddenError("Only the paying patient can start checkout")
    if booking.status != "pending" or booking.hold_until <= now():
        raise ConflictError("Reservation has ended")
    payment = await db.scalar(select(Payment).where(Payment.booking_id == booking.id))
    if not payment:
        raise ConflictError("Booking has no payment")
    if payment.checkout_id:
        return await booking_view(db, booking)
    if payment.checkout_started_at and payment.checkout_started_at < now() - timedelta(
        hours=23
    ):
        raise ConflictError("Payment requires reconciliation before another checkout")
    payment.checkout_started_at = payment.checkout_started_at or now()
    # Persisted payment ID is the stable provider idempotency key. No slot lock across HTTP.
    await db.commit()
    result = await payment_provider().checkout(payment, booking)
    payment = await db.get(
        Payment, payment.id, with_for_update=True, populate_existing=True
    )
    payment.checkout_id, payment.checkout_url = result["id"], result.get("url")
    await db.commit()
    return await booking_view(db, booking)


async def lock_booking(db, booking_id):
    initial = await db.get(Booking, booking_id)
    if not initial:
        raise NotFoundError("Booking not found")
    if initial.assignment_id:
        await get_assignment_by_id(db, initial.assignment_id, for_update=True)
    slot = await get_slot_by_id(db, initial.slot_id, for_update=True)
    booking = await db.get(
        Booking, booking_id, with_for_update=True, populate_existing=True
    )
    payment = await db.scalar(
        select(Payment)
        .where(Payment.booking_id == booking_id)
        .with_for_update()
        .execution_options(populate_existing=True)
    )
    return slot, booking, payment


async def enqueue_operation(db, payment, kind, amount):
    existing = await db.scalar(
        select(MoneyOperation).where(
            MoneyOperation.payment_id == payment.id, MoneyOperation.kind == kind
        )
    )
    if not existing:
        db.add(MoneyOperation(payment_id=payment.id, kind=kind, amount_minor=amount))
    if kind == "refund" and payment.status != "refunded":
        payment.status = "refund_pending"


async def confirm_payment(
    db, payment_id, *, external_id, amount_minor, currency, source_charge=None
):
    initial = await db.get(Payment, payment_id)
    if not initial:
        raise NotFoundError("Payment not found")
    slot, booking, payment = await lock_booking(db, initial.booking_id)
    if booking.test_mode != settings.TEST_MODE:
        raise ConflictError("Payment environment mismatch")
    if amount_minor != payment.amount_minor or currency.upper() != payment.currency:
        raise BillingError(
            "payment_mismatch", "Payment amount or currency does not match the order"
        )
    if payment.external_id and payment.external_id != external_id:
        raise ConflictError("Payment already has a different provider reference")
    if payment.status in ("paid", "refund_pending", "refunded"):
        if source_charge and not payment.source_charge:
            payment.source_charge = source_charge
        return booking
    payment.external_id, payment.source_charge = external_id, source_charge
    payment.status = "paid"
    latest = await get_latest_slot_event(db, slot.id)
    assignment_event = (
        await get_latest_assignment_event(db, booking.assignment_id)
        if booking.assignment_id
        else None
    )
    patient = await db.get(User, booking.patient_id)
    psychologist = await db.get(User, booking.psychologist_id)
    eligible = (
        booking.status == "pending"
        and booking.hold_until > now()
        and slot.start_at > now()
        and latest
        and latest.event_type in (SlotEventType.CREATED, SlotEventType.CANCELLED)
        and assignment_event
        and assignment_event.event_type == PatientAssignmentEventType.ACCEPTED
        and patient.is_active
        and not patient.is_psychologist
        and psychologist.is_active
        and psychologist.is_psychologist
    )
    if eligible:
        event = await create_slot_event(
            db,
            slot.id,
            SlotEventType.BOOKED,
            performed_by_id=booking.patient_id,
            patient_id=booking.patient_id,
        )
        booking.booked_event_id = event.id
        booking.status = "confirmed"
    else:
        if booking.status == "pending":
            booking.status = "expired"
        await enqueue_operation(db, payment, "refund", payment.amount_minor)
    await db.flush()
    return booking


async def cancel_finances(db, slot_id):
    # Caller already holds slot lock. Does not call providers inside its transaction.
    booking = await active_booking(db, slot_id)
    if not booking:
        return
    booking.status = "cancelled"
    payment = await db.scalar(
        select(Payment).where(Payment.booking_id == booking.id).with_for_update()
    )
    if payment and payment.status == "paid":
        await enqueue_operation(db, payment, "refund", payment.amount_minor)


async def finalize_finances(
    db, slot_id, booked_event_id, patient_joined, psychologist_joined
):
    booking = await db.scalar(
        select(Booking).where(Booking.booked_event_id == booked_event_id)
    )
    if not booking or booking.status != "confirmed":
        return  # Historical sessions are not retroactively charged.
    booking.status = "completed" if patient_joined and psychologist_joined else "missed"
    booking.outcome = (
        "both_present"
        if patient_joined and psychologist_joined
        else "patient_absent"
        if psychologist_joined
        else "psychologist_absent"
        if patient_joined
        else "both_absent"
    )
    booking.finalized_at = now()
    if booking.legacy:
        return
    payment = await db.scalar(
        select(Payment).where(Payment.booking_id == booking.id).with_for_update()
    )
    if not payment or payment.status != "paid":
        raise ConflictError("Cannot settle an unpaid booking")
    if psychologist_joined:
        net = booking.quote["net_minor"]
        db.add(
            Earning(
                booking_id=booking.id,
                psychologist_id=booking.psychologist_id,
                test_mode=booking.test_mode,
                net_minor=net,
                currency=payment.currency,
            )
        )
        await enqueue_operation(db, payment, "transfer", net)
    else:
        await enqueue_operation(db, payment, "refund", payment.amount_minor)


async def assert_call_paid(db, event):
    booking = await db.scalar(
        select(Booking).where(Booking.booked_event_id == event.id)
    )
    if not booking:
        raise ConflictError(
            "Booking has no billing record; migrate legacy bookings first"
        )
    if booking.legacy:
        return
    payment = await db.scalar(select(Payment).where(Payment.booking_id == booking.id))
    if (
        booking.test_mode != settings.TEST_MODE
        or booking.status != "confirmed"
        or not payment
        or payment.status != "paid"
    ):
        raise ForbiddenError("Consultation has not been paid")
