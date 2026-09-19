import asyncio
import uuid
from datetime import timedelta

import pytest
from sqlalchemy import func, select

from app.ai.models.conversation import AiConversationMode
from app.ai.providers.chat import AiProviderError
from app.ai.services.conversation import (
    create_conversation,
    get_conversation_with_messages,
)
from app.ai.services.message import send_user_message
from app.billing.access import access_summary
from app.billing.errors import BillingError
from app.billing.jobs import expire_reservations, process_operations
from app.billing.models import (
    Booking,
    Earning,
    MoneyOperation,
    Payment,
    Subscription,
    now,
)
from app.billing.pricing import calculate_quote
from app.billing.service import confirm_payment, reserve_booking
from app.billing.subscription import mock_purchase
from app.core.errors import ConflictError
from app.core.settings import settings
from app.db.session import AsyncSessionLocal
from app.models.call import Call
from app.models.call_event import CallEvent, CallEventType
from app.models.slot import Slot
from app.models.slot_event import SlotEvent
from app.services.call import join_call
from app.services.lesson_finalization_service import resolve_expired_lesson_outcomes
from app.services.patient_assignment import finish_assignment
from app.services.slot import cancel_slot_booking, get_available_slots


async def booked(domain):
    patient, psy, _, _, slot = domain
    async with AsyncSessionLocal() as db:
        booking = await reserve_booking(db, slot.id, patient, uuid.uuid4())
        payment = await db.scalar(
            select(Payment).where(Payment.booking_id == booking.id)
        )
        await confirm_payment(
            db,
            payment.id,
            external_id=f"mock_{payment.id}",
            amount_minor=payment.amount_minor,
            currency="RUB",
        )
        await db.commit()
        return booking.id, payment.id


async def end_session(booking_id, patient_here, psy_here):
    async with AsyncSessionLocal() as db:
        booking = await db.get(Booking, booking_id)
        slot = await db.get(Slot, booking.slot_id)
        slot.start_at, slot.end_at = (
            now() - timedelta(hours=2),
            now() - timedelta(hours=1),
        )
        event = await db.get(SlotEvent, booking.booked_event_id)
        for earlier in (
            await db.scalars(select(SlotEvent).where(SlotEvent.slot_id == slot.id))
        ).all():
            earlier.created_at = slot.start_at - timedelta(minutes=20)
        event.created_at = slot.start_at - timedelta(minutes=10)
        call = Call(slot_id=slot.id)
        db.add(call)
        await db.flush()
        for user_id in ([booking.patient_id] if patient_here else []) + (
            [booking.psychologist_id] if psy_here else []
        ):
            db.add(
                CallEvent(
                    call_id=call.id,
                    user_id=user_id,
                    event_type=CallEventType.JOINED,
                    created_at=slot.start_at,
                )
            )
        await db.commit()


def test_gross_price_preserves_net():
    quote = calculate_quote(300000, 1800, "RUB", (1000, 1500, 290, 30))
    assert quote["net_minor"] == 150000
    assert (
        quote["amount_minor"]
        - sum(
            quote[x]
            for x in ["tax_minor", "platform_fee_minor", "processor_fee_estimate_minor"]
        )
        >= 150000
    )


@pytest.mark.parametrize(
    "patient_here,psy_here,expected",
    [
        (True, True, "transfer"),
        (False, True, "transfer"),
        (True, False, "refund"),
        (False, False, "refund"),
    ],
)
async def test_four_outcomes_and_no_duplicate_money(
    domain, patient_here, psy_here, expected
):
    booking_id, payment_id = await booked(domain)
    async with AsyncSessionLocal() as db:
        assert await db.scalar(select(func.count()).select_from(Earning)) == 0
    await end_session(booking_id, patient_here, psy_here)
    async with AsyncSessionLocal() as db:
        assert await resolve_expired_lesson_outcomes(db) == 1
    async with AsyncSessionLocal() as db:
        assert await resolve_expired_lesson_outcomes(db) == 0
    await asyncio.gather(process_operations(), process_operations())
    async with AsyncSessionLocal() as db:
        operations = (await db.scalars(select(MoneyOperation))).all()
        assert (
            len(operations) == 1
            and operations[0].kind == expected
            and operations[0].status == "succeeded"
        )
        payment = await db.get(Payment, payment_id)
        assert payment.status == ("refunded" if expected == "refund" else "paid")
        assert await db.scalar(select(func.count()).select_from(Earning)) == (
            1 if expected == "transfer" else 0
        )


async def test_concurrent_reservations(domain):
    patient, _, _, _, slot = domain

    async def attempt():
        async with AsyncSessionLocal() as db:
            try:
                return (await reserve_booking(db, slot.id, patient, uuid.uuid4())).id
            except ConflictError:
                return None

    results = await asyncio.gather(attempt(), attempt())
    assert sum(x is not None for x in results) == 1
    async with AsyncSessionLocal() as db:
        assert await get_available_slots(db, patient) == []


async def test_idempotent_reserve_and_confirmation(domain):
    patient, _, _, _, slot = domain
    key = uuid.uuid4()
    async with AsyncSessionLocal() as db:
        a = await reserve_booking(db, slot.id, patient, key)
    async with AsyncSessionLocal() as db:
        b = await reserve_booking(db, slot.id, patient, key)
        assert a.id == b.id
        pay = await db.scalar(select(Payment).where(Payment.booking_id == b.id))
        for _ in range(2):
            await confirm_payment(
                db,
                pay.id,
                external_id="mock_id",
                amount_minor=pay.amount_minor,
                currency="RUB",
            )
            await db.commit()
        assert (
            await db.scalar(
                select(func.count())
                .select_from(SlotEvent)
                .where(SlotEvent.slot_id == slot.id)
            )
            == 2
        )


async def test_full_refund_and_rebooking(domain):
    bid, pid = await booked(domain)
    patient, _, _, _, slot = domain
    async with AsyncSessionLocal() as db:
        await cancel_slot_booking(db, slot.id, patient)
    await process_operations()
    async with AsyncSessionLocal() as db:
        payment = await db.get(Payment, pid)
        operation = await db.scalar(
            select(MoneyOperation).where(MoneyOperation.payment_id == pid)
        )
        assert (
            payment.status == "refunded"
            and operation.amount_minor == payment.amount_minor
        )
        new = await reserve_booking(db, slot.id, patient, uuid.uuid4())
        assert new.id != bid and new.status == "pending"


async def test_late_payment_refunds_without_stealing_slot(domain):
    patient, _, _, _, slot = domain
    async with AsyncSessionLocal() as db:
        old = await reserve_booking(db, slot.id, patient, uuid.uuid4())
        old.hold_until = now() - timedelta(seconds=1)
        await db.commit()
    await expire_reservations()
    async with AsyncSessionLocal() as db:
        new = await reserve_booking(db, slot.id, patient, uuid.uuid4())
        payment = await db.scalar(select(Payment).where(Payment.booking_id == old.id))
        await confirm_payment(
            db,
            payment.id,
            external_id="late",
            amount_minor=payment.amount_minor,
            currency="RUB",
        )
        await db.commit()
        assert (await db.get(Booking, new.id)).status == "pending"
        assert payment.status == "refund_pending"


async def test_finish_assignment_cancels_pending_and_paid(domain):
    _, pid = await booked(domain)
    patient, _, _, assignment, _ = domain
    async with AsyncSessionLocal() as db:
        await finish_assignment(db, assignment.id, patient.id, "Finished by patient")
    await process_operations()
    async with AsyncSessionLocal() as db:
        assert (await db.get(Payment, pid)).status == "refunded"


async def test_unpaid_call_denied(domain):
    patient, _, _, _, slot = domain
    async with AsyncSessionLocal() as db:
        await reserve_booking(db, slot.id, patient, uuid.uuid4())
        with pytest.raises(ConflictError):
            await join_call(db, slot.id, patient)


async def test_price_mismatch_does_not_confirm(domain):
    patient, _, _, _, slot = domain
    async with AsyncSessionLocal() as db:
        booking = await reserve_booking(db, slot.id, patient, uuid.uuid4())
        payment = await db.scalar(
            select(Payment).where(Payment.booking_id == booking.id)
        )
        with pytest.raises(BillingError):
            await confirm_payment(
                db, payment.id, external_id="wrong", amount_minor=1, currency="RUB"
            )


async def test_subscription_retry_and_free_limit_all_chats(domain):
    patient = domain[0]
    async with AsyncSessionLocal() as db:
        chats = [
            await create_conversation(db, patient, "test", AiConversationMode.SELF_HELP)
            for _ in range(4)
        ]

    async def send(chat):
        async with AsyncSessionLocal() as db:
            try:
                await send_user_message(db, chat.id, patient, "Hello", uuid.uuid4())
                return True
            except BillingError as error:
                assert error.code == "daily_limit_exceeded"
                return False

    assert sum(await asyncio.gather(*(send(c) for c in chats))) == 3
    key = uuid.uuid4()
    async with AsyncSessionLocal() as db:
        a = await mock_purchase(db, patient.id, key)
        b = await mock_purchase(db, patient.id, key)
        assert a["expires_at"] == b["expires_at"]
    assert all(await asyncio.gather(*(send(c) for c in chats)))


async def test_ai_retry_and_failure_do_not_spend_twice(domain, monkeypatch):
    patient = domain[0]
    async with AsyncSessionLocal() as db:
        chat = await create_conversation(
            db, patient, "test", AiConversationMode.SELF_HELP
        )
        request_id = uuid.uuid4()
        await send_user_message(db, chat.id, patient, "Hello", request_id)
        await send_user_message(db, chat.id, patient, "Hello", request_id)
        assert (await access_summary(db, patient.id))["remaining_messages"] == 2

    async def fail(**kwargs):
        raise AiProviderError("test outage")

    monkeypatch.setattr("app.ai.services.message.generate_ai_reply", fail)
    async with AsyncSessionLocal() as db:
        with pytest.raises(AiProviderError):
            await send_user_message(db, chat.id, patient, "Failure", uuid.uuid4())
        assert (await access_summary(db, patient.id))["remaining_messages"] == 2


async def test_guided_and_care_plan_access(domain):
    from app.ai.services.ai_care_plan import (
        activate_care_plan_version,
        create_care_plan,
        get_patient_care_plan,
    )

    patient, psy, _, assignment, _ = domain
    async with AsyncSessionLocal() as db:
        plan, version = await create_care_plan(
            db, assignment.id, psy.id, "Private instructions", "Patient recommendation"
        )
        await activate_care_plan_version(db, assignment.id, psy.id, version.id)
        with pytest.raises(BillingError):
            await get_patient_care_plan(db, assignment.id, patient.id)
        with pytest.raises(BillingError):
            await create_conversation(db, patient, "Guided", AiConversationMode.GUIDED)
        await mock_purchase(db, patient.id, uuid.uuid4())
        chat = await create_conversation(
            db, patient, "Guided", AiConversationMode.GUIDED
        )
        await send_user_message(db, chat.id, patient, "Hi", uuid.uuid4())
        sub = await db.scalar(
            select(Subscription).where(Subscription.user_id == patient.id)
        )
        sub.expires_at = now() - timedelta(seconds=1)
        await db.commit()
        assert await get_conversation_with_messages(db, patient, chat.id)
        with pytest.raises(BillingError):
            await send_user_message(db, chat.id, patient, "New", uuid.uuid4())


async def test_mock_endpoints_off_in_live(domain, monkeypatch):
    from app.billing.routes import mock_only
    from app.core.errors import NotFoundError

    monkeypatch.setattr(settings, "TEST_MODE", False)
    with pytest.raises(NotFoundError):
        mock_only()


async def test_provider_failure_retries_without_losing_operation(domain, monkeypatch):
    from app.billing.providers.mock import MockPaymentProvider

    _, pid = await booked(domain)
    async with AsyncSessionLocal() as db:
        await cancel_slot_booking(db, domain[4].id, domain[0])
    original = MockPaymentProvider.refund

    async def fail(*args):
        raise TimeoutError("simulated provider outage")

    monkeypatch.setattr(MockPaymentProvider, "refund", fail)
    await process_operations()
    async with AsyncSessionLocal() as db:
        op = await db.scalar(
            select(MoneyOperation).where(MoneyOperation.payment_id == pid)
        )
        assert (
            op.status == "pending"
            and op.attempts == 1
            and op.last_error == "TimeoutError"
        )
        op.retry_at = now() - timedelta(seconds=1)
        await db.commit()
    monkeypatch.setattr(MockPaymentProvider, "refund", original)
    await process_operations()
    async with AsyncSessionLocal() as db:
        op = await db.scalar(
            select(MoneyOperation).where(MoneyOperation.payment_id == pid)
        )
        assert op.status == "succeeded" and op.attempts == 2
        assert (await db.get(Payment, pid)).status == "refunded"


def test_daily_period_switches_at_moscow_midnight(monkeypatch):
    from datetime import datetime, timezone

    from app.billing.access import usage_period

    monkeypatch.setattr(
        "app.billing.access.now",
        lambda: datetime(2026, 9, 18, 20, 59, tzinfo=timezone.utc),
    )
    day, reset = usage_period()
    assert day.isoformat() == "2026-09-18" and reset.hour == 21
    monkeypatch.setattr("app.billing.access.now", lambda: reset)
    next_day, next_reset = usage_period()
    assert next_day.isoformat() == "2026-09-19" and next_reset == reset + timedelta(
        days=1
    )


def test_tiny_rate_cannot_create_zero_payment():
    with pytest.raises(BillingError) as error:
        calculate_quote(1, 900, "RUB", (0, 0, 0, 0))
    assert error.value.code == "invalid_price"
