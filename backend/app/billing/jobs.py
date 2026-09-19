import logging
import uuid
from datetime import timedelta

from sqlalchemy import select

from app.billing.models import Booking, MoneyOperation, Payment, ProviderEvent, now
from app.billing.providers import payment_provider
from app.billing.service import confirm_payment
from app.billing.subscription import sync_subscription
from app.core.settings import settings
from app.db.session import AsyncSessionLocal
from app.models.slot import Slot
from app.models.user import User

logger = logging.getLogger(__name__)


async def process_events():
    async with AsyncSessionLocal() as db:
        ids = list(
            (
                await db.scalars(
                    select(ProviderEvent.id)
                    .where(ProviderEvent.status == "pending")
                    .order_by(ProviderEvent.created_at)
                    .limit(100)
                )
            ).all()
        )
    for event_id in ids:
        async with AsyncSessionLocal() as db:
            event = await db.scalar(
                select(ProviderEvent)
                .where(ProviderEvent.id == event_id)
                .with_for_update(skip_locked=True)
            )
            if not event or event.status != "pending":
                continue
            try:
                payload = event.payload
                if event.provider == "stripe":
                    obj = payload.get("data", {}).get("object", {})
                    if payload.get("type") == "payment_intent.succeeded":
                        payment_id = obj.get("metadata", {}).get("payment_id")
                        if payment_id:
                            await confirm_payment(
                                db,
                                uuid.UUID(payment_id),
                                external_id=obj["id"],
                                amount_minor=obj["amount_received"],
                                currency=obj["currency"],
                                source_charge=obj.get("latest_charge"),
                            )
                    elif payload.get("type") == "account.updated":
                        from app.billing.models import PsychologistBilling

                        profile = await db.scalar(
                            select(PsychologistBilling)
                            .where(PsychologistBilling.stripe_account_id == obj["id"])
                            .with_for_update()
                        )
                        if profile:
                            profile.charges_enabled = obj.get("charges_enabled", False)
                            profile.payouts_enabled = obj.get("payouts_enabled", False)
                elif event.provider == "revenuecat":
                    obj = payload.get("event", {})
                    candidates = [
                        obj.get("app_user_id"),
                        obj.get("original_app_user_id"),
                        *obj.get("aliases", []),
                        *obj.get("transferred_from", []),
                        *obj.get("transferred_to", []),
                    ]
                    users = set()
                    for candidate in candidates:
                        try:
                            users.add(uuid.UUID(candidate))
                        except (ValueError, TypeError, AttributeError):
                            continue
                    for user_id in sorted(users):
                        if await db.get(User, user_id):
                            await sync_subscription(db, user_id, commit=False)
                event.status = "processed"
                event.last_error = None
                await db.commit()
            except Exception as error:
                await db.rollback()
                event = await db.get(ProviderEvent, event_id)
                event.last_error = type(error).__name__
                await db.commit()
                logger.warning(
                    "Billing event %s needs retry (%s)", event_id, type(error).__name__
                )


async def expire_reservations():
    async with AsyncSessionLocal() as db:
        # Slot is the common lock with booking, cancellation and webhook confirmation.
        slots = list(
            (
                await db.scalars(
                    select(Slot)
                    .join(Booking, Booking.slot_id == Slot.id)
                    .where(Booking.status == "pending", Booking.hold_until <= now())
                    .with_for_update(of=Slot, skip_locked=True)
                    .limit(100)
                )
            ).all()
        )
        for slot in slots:
            bookings = (
                await db.scalars(
                    select(Booking).where(
                        Booking.slot_id == slot.id,
                        Booking.status == "pending",
                        Booking.hold_until <= now(),
                    )
                )
            ).all()
            for booking in bookings:
                booking.status = "expired"
        await db.commit()


async def process_operations():
    for _ in range(100):
        async with AsyncSessionLocal() as db:
            operation = await db.scalar(
                select(MoneyOperation)
                .join(Payment)
                .join(Booking)
                .where(
                    Booking.test_mode == settings.TEST_MODE,
                    MoneyOperation.status.in_(["pending", "processing"]),
                    MoneyOperation.retry_at <= now(),
                    (
                        MoneyOperation.lease_until.is_(None)
                        | (MoneyOperation.lease_until < now())
                    ),
                )
                .order_by(MoneyOperation.created_at)
                .with_for_update(of=MoneyOperation, skip_locked=True)
                .limit(1)
            )
            if not operation:
                break
            operation_id = operation.id
            if (
                not settings.TEST_MODE
                and operation.attempts > 0
                and not operation.external_id
                and operation.created_at < now() - timedelta(hours=23)
            ):
                operation.status = "needs_review"
                operation.last_error = (
                    "Unknown provider result beyond safe idempotency retry window"
                )
                operation.lease_until = None
                await db.commit()
                continue
            operation.status = "processing"
            operation.lease_until = now() + timedelta(minutes=2)
            operation.attempts += 1
            payment = await db.get(Payment, operation.payment_id)
            await db.commit()  # No database lock is held during the provider call.
            try:
                provider = payment_provider()
                result = await (
                    provider.refund(payment, operation)
                    if operation.kind == "refund"
                    else provider.transfer(payment, operation)
                )
                operation = await db.get(
                    MoneyOperation,
                    operation_id,
                    with_for_update=True,
                    populate_existing=True,
                )
                operation.external_id = result["id"]
                operation.lease_until = None
                if result.get("status") == "succeeded":
                    operation.status = "succeeded"
                    if operation.kind == "refund":
                        payment = await db.get(
                            Payment, operation.payment_id, with_for_update=True
                        )
                        payment.status = "refunded"
                elif result.get("status") in ("failed", "canceled"):
                    operation.status = "failed"
                    operation.last_error = (
                        "Provider rejected operation; admin attention required"
                    )
                else:
                    operation.status = "pending"
                    operation.retry_at = now() + timedelta(minutes=1)
                await db.commit()
            except Exception as error:
                await db.rollback()
                operation = await db.get(
                    MoneyOperation, operation_id, with_for_update=True
                )
                operation.status = "pending"
                operation.lease_until = None
                operation.retry_at = now() + timedelta(
                    seconds=min(3600, 15 * 2 ** min(operation.attempts, 8))
                )
                operation.last_error = type(error).__name__
                await db.commit()
                logger.warning(
                    "Billing operation %s needs retry (%s)",
                    operation.id,
                    type(error).__name__,
                )


async def reconcile_payments():
    if settings.TEST_MODE or not settings.BILLING_LIVE_ENABLED:
        return
    async with AsyncSessionLocal() as db:
        payments = list(
            (
                await db.scalars(
                    select(Payment)
                    .where(
                        Payment.provider == "stripe",
                        Payment.status == "pending",
                        Payment.checkout_started_at.is_not(None),
                    )
                    .order_by(Payment.created_at)
                    .limit(100)
                )
            ).all()
        )
    for payment in payments:
        try:
            provider = payment_provider(False)
            async with AsyncSessionLocal() as db:
                if payment.created_at < now() - timedelta(hours=48):
                    current = await db.get(Payment, payment.id, with_for_update=True)
                    if current.status == "pending":
                        current.status = "needs_review"
                    await db.commit()
                    continue
                if not payment.checkout_id:
                    booking = await db.get(Booking, payment.booking_id)
                    if payment.checkout_started_at < now() - timedelta(hours=23):
                        current = await db.get(
                            Payment, payment.id, with_for_update=True
                        )
                        if current.status == "pending":
                            current.status = "needs_review"
                        await db.commit()
                        continue
                    result = await provider.checkout(payment, booking)
                    current = await db.get(Payment, payment.id, with_for_update=True)
                    current.checkout_id, current.checkout_url = (
                        result["id"],
                        result.get("url"),
                    )
                    await db.commit()
                    payment.checkout_id = current.checkout_id
                obj = await provider.retrieve(payment)
                if obj and obj.get("status") == "succeeded":
                    await confirm_payment(
                        db,
                        payment.id,
                        external_id=obj["id"],
                        amount_minor=obj["amount_received"],
                        currency=obj["currency"],
                        source_charge=obj.get("latest_charge"),
                    )
                    await db.commit()
        except Exception as error:
            logger.warning(
                "Payment reconciliation %s failed (%s)",
                payment.id,
                type(error).__name__,
            )


async def billing_job():
    await expire_reservations()
    await process_events()
    await reconcile_payments()
    await reconcile_subscriptions()
    await reconcile_processing_fees()
    await process_operations()


async def reconcile_processing_fees():
    """Store the actual charge fee in the provider's settlement currency."""
    if settings.TEST_MODE or not settings.BILLING_LIVE_ENABLED:
        return
    from app.billing.providers.stripe_connect import StripeConnectProvider

    async with AsyncSessionLocal() as db:
        payments = list(
            (
                await db.scalars(
                    select(Payment)
                    .where(
                        Payment.provider == "stripe",
                        Payment.source_charge.is_not(None),
                        Payment.actual_fee_minor.is_(None),
                    )
                    .order_by(Payment.created_at)
                    .limit(100)
                )
            ).all()
        )
    for payment in payments:
        try:
            charge = await StripeConnectProvider().charge_details(payment.source_charge)
            transaction = charge.get("balance_transaction")
            if isinstance(transaction, dict) and isinstance(
                transaction.get("fee"), int
            ):
                async with AsyncSessionLocal() as db:
                    record = await db.get(Payment, payment.id, with_for_update=True)
                    record.actual_fee_minor = transaction["fee"]
                    record.actual_fee_currency = transaction["currency"].upper()
                    await db.commit()
        except Exception as error:
            logger.warning(
                "Fee reconciliation %s failed (%s)", payment.id, type(error).__name__
            )


async def reconcile_subscriptions():
    """Recover missed renewal/refund events, including subscriptions that just expired."""
    if settings.TEST_MODE or not settings.BILLING_LIVE_ENABLED:
        return
    from app.billing.models import Subscription

    async with AsyncSessionLocal() as db:
        user_ids = list(
            (
                await db.scalars(
                    select(Subscription.user_id)
                    .where(
                        Subscription.test_mode.is_(False),
                        Subscription.updated_at < now() - timedelta(hours=1),
                    )
                    .order_by(Subscription.updated_at)
                    .limit(100)
                )
            ).all()
        )
    for user_id in user_ids:
        try:
            async with AsyncSessionLocal() as db:
                await sync_subscription(db, user_id)
        except Exception as error:
            logger.warning(
                "Subscription reconciliation %s failed (%s)",
                user_id,
                type(error).__name__,
            )
