import hmac
import uuid
from datetime import datetime
from typing import Literal
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, Field, model_validator
from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import current_active_user, require_psychologist, require_superuser
from app.billing.access import access_summary, lock_account
from app.billing.errors import BillingError
from app.billing.models import (
    Booking,
    Earning,
    MoneyOperation,
    Payment,
    PricingPolicy,
    ProviderEvent,
    PsychologistBilling,
    Subscription,
    now,
)
from app.billing.pricing import quote_slot
from app.billing.providers.stripe_connect import (
    StripeConnectProvider,
    verify_stripe_event,
)
from app.billing.service import (
    booking_view,
    checkout,
    confirm_payment,
    lock_booking,
    owned_booking,
)
from app.billing.subscription import mock_purchase, sync_subscription
from app.core.errors import ConflictError, ForbiddenError, NotFoundError
from app.core.settings import settings
from app.db.deps import get_db
from app.models.user import User

router = APIRouter(prefix="/billing", tags=["Billing"])


class MockAttendance(BaseModel):
    patient_present: bool
    psychologist_present: bool


@router.post("/mock/bookings/{booking_id}/finish")
async def simulate_finish(
    booking_id: uuid.UUID,
    data: MockAttendance,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_superuser),
):
    mock_only()
    slot, booking, payment = await lock_booking(db, booking_id)
    if not booking.test_mode or booking.legacy:
        raise ForbiddenError("Only mock bookings can be simulated")
    if booking.status in ("completed", "missed"):
        return await booking_view(db, booking)
    if booking.status != "confirmed":
        raise ConflictError("Pay the booking before simulating the result")
    from app.billing.service import finalize_finances
    from app.crud.slot import create_slot_event
    from app.models.slot_event import SlotEventType

    await finalize_finances(
        db,
        slot.id,
        booking.booked_event_id,
        data.patient_present,
        data.psychologist_present,
    )
    await create_slot_event(
        db,
        slot.id,
        SlotEventType.COMPLETED
        if data.patient_present and data.psychologist_present
        else SlotEventType.MISSED,
        performed_by_id=user.id,
        patient_id=booking.patient_id,
        comment="TEST_MODE: simulated attendance result",
    )
    await db.commit()
    return await booking_view(db, booking)


class RequestKey(BaseModel):
    request_id: uuid.UUID


class RateIn(BaseModel):
    hourly_net_minor: int = Field(gt=0, le=100_000_000)


class MockResult(BaseModel):
    outcome: Literal["success", "failure"] = "success"


class PolicyIn(BaseModel):
    tax_bps: int = Field(ge=0, lt=10000)
    platform_bps: int = Field(ge=0, lt=10000)
    processor_bps: int = Field(ge=0, lt=10000)
    processor_fixed_minor: int = Field(ge=0, le=100_000_000)

    @model_validator(mode="after")
    def total(self):
        if self.tax_bps + self.platform_bps + self.processor_bps >= 10000:
            raise ValueError("Combined rates must be less than 100%")
        return self


def mock_only():
    if not settings.TEST_MODE:
        raise NotFoundError("Not found")


@router.get("/me")
async def me(
    db: AsyncSession = Depends(get_db), user: User = Depends(current_active_user)
):
    return await access_summary(db, user.id)


@router.post("/subscription/sync")
async def sync(
    db: AsyncSession = Depends(get_db), user: User = Depends(current_active_user)
):
    return await sync_subscription(db, user.id)


@router.post("/mock/subscription")
async def buy_mock(
    data: RequestKey,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
    _: None = Depends(mock_only),
):
    if user.is_psychologist:
        raise ForbiddenError("Only patients can buy AI access")
    return await mock_purchase(db, user.id, data.request_id)


@router.delete("/mock/subscription")
async def expire_mock(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
    _: None = Depends(mock_only),
):
    await lock_account(db, user.id)
    sub = await db.scalar(
        select(Subscription).where(
            Subscription.user_id == user.id, Subscription.test_mode.is_(True)
        )
    )
    if sub:
        sub.expires_at = now()
    await db.commit()
    return await access_summary(db, user.id)


@router.get("/psychologist/me")
async def profile(
    db: AsyncSession = Depends(get_db), user: User = Depends(require_psychologist)
):
    result = await db.get(PsychologistBilling, user.id)
    return dict(
        hourly_net_minor=result.hourly_net_minor if result else None,
        currency=result.currency if result else settings.BILLING_CURRENCY,
        test_mode=settings.TEST_MODE,
        connected=settings.TEST_MODE
        or bool(result and result.charges_enabled and result.payouts_enabled),
    )


@router.patch("/psychologist/me")
async def set_rate(
    data: RateIn,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_psychologist),
):
    await db.execute(
        insert(PsychologistBilling)
        .values(
            user_id=user.id,
            hourly_net_minor=data.hourly_net_minor,
            currency=settings.BILLING_CURRENCY,
            charges_enabled=False,
            payouts_enabled=False,
        )
        .on_conflict_do_update(
            index_elements=[PsychologistBilling.user_id],
            set_={
                "hourly_net_minor": data.hourly_net_minor,
                "currency": settings.BILLING_CURRENCY,
            },
        )
    )
    await db.commit()
    return await profile(db, user)


@router.post("/psychologist/onboarding")
async def onboarding(
    db: AsyncSession = Depends(get_db), user: User = Depends(require_psychologist)
):
    if settings.TEST_MODE:
        return {"test_mode": True, "connected": True, "url": None}
    await lock_account(db, user.id)
    result = await db.get(PsychologistBilling, user.id)
    if not result:
        raise ConflictError("Set your hourly rate first")
    provider = StripeConnectProvider()
    if not result.stripe_account_id:
        if not settings.STRIPE_CONNECT_COUNTRY:
            raise BillingError("country_required", "Connect country must be configured")
        account = await provider.request(
            "POST",
            "accounts",
            key=f"psychologist:{user.id}",
            data={
                "type": "express",
                "country": settings.STRIPE_CONNECT_COUNTRY,
                "capabilities[transfers][requested]": "true",
                "capabilities[card_payments][requested]": "true",
                "metadata[user_id]": str(user.id),
            },
        )
        result.stripe_account_id = account["id"]
        await db.commit()
    account = await provider.account(result.stripe_account_id)
    result.charges_enabled, result.payouts_enabled = (
        account.get("charges_enabled", False),
        account.get("payouts_enabled", False),
    )
    await db.commit()
    link = await provider.request(
        "POST",
        "account_links",
        data={
            "account": result.stripe_account_id,
            "type": "account_onboarding",
            "return_url": settings.FRONTEND_URL + "/billing/onboarding",
            "refresh_url": settings.FRONTEND_URL + "/billing/onboarding",
        },
    )
    return {
        "url": link["url"],
        "connected": result.charges_enabled and result.payouts_enabled,
    }


@router.post("/admin/pricing-policy")
async def policy(
    data: PolicyIn,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_superuser),
):
    record = PricingPolicy(
        **data.model_dump(), test_mode=settings.TEST_MODE, created_by_id=user.id
    )
    db.add(record)
    await db.commit()
    return {"id": record.id, "test_mode": settings.TEST_MODE, **data.model_dump()}


@router.get("/slots/{slot_id}/quote")
async def quote(
    slot_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
):
    from app.crud.slot import get_slot_by_id

    slot = await get_slot_by_id(db, slot_id)
    if not slot:
        raise NotFoundError("Slot not found")
    return await quote_slot(db, slot)


@router.get("/bookings")
async def bookings(
    db: AsyncSession = Depends(get_db), user: User = Depends(current_active_user)
):
    records = (
        await db.scalars(
            select(Booking)
            .where(
                Booking.test_mode == settings.TEST_MODE,
                (Booking.patient_id == user.id) | (Booking.psychologist_id == user.id),
            )
            .order_by(Booking.created_at.desc())
            .limit(100)
        )
    ).all()
    return [await booking_view(db, b) for b in records]


@router.get("/bookings/{booking_id}")
async def get_booking(
    booking_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
):
    return await booking_view(db, await owned_booking(db, booking_id, user))


@router.post("/bookings/{booking_id}/checkout")
async def begin_checkout(
    booking_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
):
    return await checkout(db, booking_id, user)


@router.post("/bookings/{booking_id}/cancel")
async def cancel(
    booking_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
):
    initial = await owned_booking(db, booking_id, user)
    if initial.patient_id != user.id:
        raise ForbiddenError("Use slot cancellation with a comment as the psychologist")
    slot, booking, payment = await lock_booking(db, booking_id)
    if booking.status == "pending":
        booking.status = "cancelled"
        await db.commit()
    elif booking.status == "confirmed":
        from app.services.slot import cancel_slot_booking

        await cancel_slot_booking(db, slot.id, user)
    elif booking.status != "cancelled":
        raise ConflictError("Booking cannot be cancelled")
    return await booking_view(db, booking)


@router.post("/mock/bookings/{booking_id}/pay")
async def mock_pay(
    booking_id: uuid.UUID,
    data: MockResult,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
    _: None = Depends(mock_only),
):
    initial = await owned_booking(db, booking_id, user)
    if initial.patient_id != user.id or not initial.test_mode:
        raise ForbiddenError("Only the booking patient can simulate payment")
    slot, booking, payment = await lock_booking(db, booking_id)
    if not payment:
        raise ConflictError("Legacy booking does not have a payment")
    if data.outcome == "failure":
        if payment.status != "pending":
            raise ConflictError("Payment already resolved")
        payment.status = "failed"
        booking.status = "cancelled"
    else:
        booking = await confirm_payment(
            db,
            payment.id,
            external_id=f"mock_payment_{payment.id}",
            amount_minor=payment.amount_minor,
            currency=payment.currency,
        )
    await db.commit()
    return await booking_view(db, booking)


@router.get("/psychologist/earnings")
async def earnings(
    year: int = 0,
    month: int = 0,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_psychologist),
):
    local = now().astimezone(ZoneInfo(settings.BILLING_TIMEZONE))
    year, month = year or local.year, month or local.month
    try:
        start = datetime(year, month, 1, tzinfo=local.tzinfo)
        end = (
            datetime(year + 1, 1, 1, tzinfo=local.tzinfo)
            if month == 12
            else datetime(year, month + 1, 1, tzinfo=local.tzinfo)
        )
    except ValueError:
        raise BillingError("invalid_period", "Invalid year/month", status_code=400)
    rows = (
        await db.execute(
            select(
                Earning.currency, func.sum(Earning.net_minor), func.count(Earning.id)
            )
            .where(
                Earning.psychologist_id == user.id,
                Earning.test_mode == settings.TEST_MODE,
                Earning.created_at >= start,
                Earning.created_at < end,
            )
            .group_by(Earning.currency)
        )
    ).all()
    transferred = dict(
        (
            await db.execute(
                select(Earning.currency, func.sum(MoneyOperation.amount_minor))
                .join(Payment, Payment.booking_id == Earning.booking_id)
                .join(MoneyOperation, MoneyOperation.payment_id == Payment.id)
                .where(
                    Earning.psychologist_id == user.id,
                    Earning.test_mode == settings.TEST_MODE,
                    Earning.created_at >= start,
                    Earning.created_at < end,
                    MoneyOperation.kind == "transfer",
                    MoneyOperation.status == "succeeded",
                )
                .group_by(Earning.currency)
            )
        ).all()
    )
    return {
        "year": year,
        "month": month,
        "timezone": settings.BILLING_TIMEZONE,
        "test_mode": settings.TEST_MODE,
        "totals": [
            dict(
                currency=c,
                earned_net_minor=int(n),
                sessions=count,
                transferred_minor=int(transferred.get(c, 0)),
            )
            for c, n, count in rows
        ],
        "bank_payouts": "Managed by the connected account; a transfer is not a bank payout",
    }


@router.get("/admin/operations")
async def operations(
    db: AsyncSession = Depends(get_db), user: User = Depends(require_superuser)
):
    records = (
        await db.scalars(
            select(MoneyOperation)
            .join(Payment)
            .join(Booking)
            .where(Booking.test_mode == settings.TEST_MODE)
            .order_by(MoneyOperation.created_at.desc())
            .limit(100)
        )
    ).all()
    return [
        dict(
            id=o.id,
            payment_id=o.payment_id,
            kind=o.kind,
            amount_minor=o.amount_minor,
            status=o.status,
            attempts=o.attempts,
            last_error=o.last_error,
        )
        for o in records
    ]


@router.get("/admin/payments")
async def payment_audit(
    db: AsyncSession = Depends(get_db), user: User = Depends(require_superuser)
):
    rows = (
        await db.execute(
            select(Payment, Booking)
            .join(Booking)
            .where(Booking.test_mode == settings.TEST_MODE)
            .order_by(Payment.created_at.desc())
            .limit(100)
        )
    ).all()
    return [
        dict(
            id=p.id,
            booking_id=b.id,
            status=p.status,
            amount_minor=p.amount_minor,
            currency=p.currency,
            actual_fee_minor=p.actual_fee_minor,
            actual_fee_currency=p.actual_fee_currency,
            external_id=p.external_id,
            checkout_id=p.checkout_id,
            outcome=b.outcome,
        )
        for p, b in rows
    ]


@router.get("/admin/events")
async def event_audit(
    db: AsyncSession = Depends(get_db), user: User = Depends(require_superuser)
):
    if settings.TEST_MODE:
        return []
    rows = (
        await db.scalars(
            select(ProviderEvent).order_by(ProviderEvent.created_at.desc()).limit(100)
        )
    ).all()
    return [
        dict(
            id=e.id,
            provider=e.provider,
            external_id=e.external_id,
            status=e.status,
            last_error=e.last_error,
        )
        for e in rows
    ]


@router.post("/mock/run-jobs")
async def run_jobs(
    user: User = Depends(require_superuser), _: None = Depends(mock_only)
):
    from app.billing.jobs import billing_job
    from app.db.session import AsyncSessionLocal
    from app.services.lesson_finalization_service import resolve_expired_lesson_outcomes

    async with AsyncSessionLocal() as db:
        finalized = await resolve_expired_lesson_outcomes(db)
    await billing_job()
    return {"finalized": finalized}


async def save_event(db, provider, external_id, payload):
    if not isinstance(external_id, str) or not external_id or len(external_id) > 200:
        raise BillingError("invalid_event", "Invalid event ID", status_code=400)
    await db.execute(
        insert(ProviderEvent)
        .values(
            id=uuid.uuid4(),
            provider=provider,
            external_id=external_id,
            payload=payload,
            status="pending",
            created_at=now(),
        )
        .on_conflict_do_nothing(
            index_elements=[ProviderEvent.provider, ProviderEvent.external_id]
        )
    )
    await db.commit()


@router.post("/webhooks/stripe")
async def stripe_webhook(request: Request, db: AsyncSession = Depends(get_db)):
    if settings.TEST_MODE:
        raise NotFoundError("Not found")
    body = await request.body()
    if len(body) > 1_000_000:
        raise BillingError("invalid_event", "Event too large", status_code=413)
    event = verify_stripe_event(body, request.headers.get("stripe-signature", ""))
    if not event.get("livemode"):
        return {"ignored": "sandbox"}
    await save_event(db, "stripe", event.get("id"), event)
    return {"received": True}


@router.post("/webhooks/revenuecat")
async def revenuecat_webhook(request: Request, db: AsyncSession = Depends(get_db)):
    if settings.TEST_MODE:
        raise NotFoundError("Not found")
    if not settings.REVENUECAT_WEBHOOK_TOKEN or not hmac.compare_digest(
        request.headers.get("authorization", ""), settings.REVENUECAT_WEBHOOK_TOKEN
    ):
        raise ForbiddenError("Invalid webhook authorization")
    body = await request.body()
    if len(body) > 1_000_000:
        raise BillingError("invalid_event", "Event too large", status_code=413)
    try:
        import json

        payload = json.loads(body)
        event = payload["event"]
        if event.get("environment") == "SANDBOX":
            return {"ignored": "sandbox"}
        await save_event(db, "revenuecat", event.get("id"), payload)
    except (ValueError, KeyError, TypeError, AttributeError):
        raise BillingError("invalid_event", "Invalid event body", status_code=400)
    return {"received": True}
