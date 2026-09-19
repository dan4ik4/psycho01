import hashlib
import hmac
import json
import time
import uuid
from datetime import timedelta

import httpx
import pytest
from sqlalchemy import func, select

from app.billing.access import paid_access
from app.billing.errors import BillingError
from app.billing.jobs import process_events
from app.billing.models import ProviderEvent, Subscription, now
from app.billing.providers.stripe_connect import verify_stripe_event
from app.billing.subscription import sync_subscription
from app.core.settings import settings
from app.db.session import AsyncSessionLocal
from app.main import app


def signature(body, timestamp=None):
    timestamp = int(time.time()) if timestamp is None else timestamp
    digest = hmac.new(
        b"local-webhook-test", str(timestamp).encode() + b"." + body, hashlib.sha256
    ).hexdigest()
    return f"t={timestamp},v1={digest}"


def test_stripe_rejects_forged_stale_and_malformed_events(monkeypatch):
    monkeypatch.setattr(settings, "STRIPE_WEBHOOK_SECRET", "local-webhook-test")
    body = b'{"id":"evt_test"}'
    assert verify_stripe_event(body, signature(body))["id"] == "evt_test"
    for payload, signed in [
        (body, "broken"),
        (body, signature(body, int(time.time()) - 600)),
        (b"[]", signature(b"[]")),
        (body + b" ", signature(body)),
    ]:
        with pytest.raises(BillingError):
            verify_stripe_event(payload, signed)


async def test_webhooks_authentication_deduplication_and_sandbox(monkeypatch):
    monkeypatch.setattr(settings, "TEST_MODE", False)
    monkeypatch.setattr(settings, "STRIPE_WEBHOOK_SECRET", "local-webhook-test")
    monkeypatch.setattr(settings, "REVENUECAT_WEBHOOK_TOKEN", "local-revenuecat-test")
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://test"
    ) as client:
        body = json.dumps(
            {"id": "evt_live", "livemode": True, "type": "unhandled"}
        ).encode()
        assert (
            await client.post("/api/v1/billing/webhooks/stripe", content=body)
        ).status_code == 400
        for _ in range(2):
            assert (
                await client.post(
                    "/api/v1/billing/webhooks/stripe",
                    content=body,
                    headers={"stripe-signature": signature(body)},
                )
            ).status_code == 200
        sandbox = json.dumps({"id": "evt_sandbox", "livemode": False}).encode()
        assert (
            await client.post(
                "/api/v1/billing/webhooks/stripe",
                content=sandbox,
                headers={"stripe-signature": signature(sandbox)},
            )
        ).json() == {"ignored": "sandbox"}
        assert (
            await client.post(
                "/api/v1/billing/webhooks/revenuecat", json={"event": {"id": "rc1"}}
            )
        ).status_code == 403
        for _ in range(2):
            response = await client.post(
                "/api/v1/billing/webhooks/revenuecat",
                json={"event": {"id": "rc1", "environment": "PRODUCTION"}},
                headers={"authorization": "local-revenuecat-test"},
            )
            assert response.status_code == 200
    async with AsyncSessionLocal() as db:
        assert await db.scalar(select(func.count()).select_from(ProviderEvent)) == 2
    await process_events()
    async with AsyncSessionLocal() as db:
        assert (
            await db.scalar(
                select(func.count())
                .select_from(ProviderEvent)
                .where(ProviderEvent.status == "processed")
            )
            == 2
        )


async def test_authoritative_subscription_sync_expiry_grace_and_sandbox(
    domain, monkeypatch
):
    monkeypatch.setattr(settings, "TEST_MODE", False)
    user_id = domain[0].id
    expiry = now() + timedelta(days=3)
    data = {
        "entitlements": {
            settings.REVENUECAT_ENTITLEMENT: {
                "product_identifier": "monthly",
                "expires_date": expiry.isoformat(),
            }
        },
        "subscriptions": {
            "monthly": {
                "is_sandbox": False,
                "unsubscribe_detected_at": now().isoformat(),
            }
        },
    }

    async def subscriber(self, received_id):
        assert received_id == user_id
        return data

    monkeypatch.setattr(
        "app.billing.subscription.RevenueCatProvider.subscriber", subscriber
    )
    async with AsyncSessionLocal() as db:
        await sync_subscription(db, user_id)
        sub = await paid_access(db, user_id)
        assert sub and sub.expires_at == expiry and not sub.will_renew
        data["subscriptions"]["monthly"]["is_sandbox"] = True
        await sync_subscription(db, user_id)
        assert not await paid_access(db, user_id)
        data["subscriptions"]["monthly"]["is_sandbox"] = False
        data["entitlements"][settings.REVENUECAT_ENTITLEMENT]["expires_date"] = (
            now() - timedelta(days=1)
        ).isoformat()
        data["subscriptions"]["monthly"]["grace_period_expires_date"] = (
            expiry.isoformat()
        )
        await sync_subscription(db, user_id)
        assert await paid_access(db, user_id)
        data["entitlements"] = {}
        await sync_subscription(db, user_id)
        assert not await paid_access(db, user_id)


async def test_revenuecat_event_reconciles_aliases(domain, monkeypatch):
    monkeypatch.setattr(settings, "TEST_MODE", False)
    user_id = domain[0].id

    async def subscriber(self, received_id):
        assert received_id == user_id
        return {}

    monkeypatch.setattr(
        "app.billing.subscription.RevenueCatProvider.subscriber", subscriber
    )
    async with AsyncSessionLocal() as db:
        db.add(
            Subscription(
                user_id=user_id,
                test_mode=False,
                provider="revenuecat",
                expires_at=now() + timedelta(days=5),
            )
        )
        db.add(
            ProviderEvent(
                provider="revenuecat",
                external_id=str(uuid.uuid4()),
                payload={
                    "event": {
                        "app_user_id": "$RCAnonymousID:x",
                        "aliases": [str(user_id)],
                    }
                },
            )
        )
        await db.commit()
    await process_events()
    async with AsyncSessionLocal() as db:
        assert not await paid_access(db, user_id)
        assert (await db.scalar(select(ProviderEvent))).status == "processed"


async def test_lost_checkout_response_recovers_after_reservation_expired(
    domain, monkeypatch
):
    from app.billing.jobs import reconcile_payments
    from app.billing.models import Booking, Payment
    from app.billing.service import reserve_booking

    async with AsyncSessionLocal() as db:
        booking = await reserve_booking(db, domain[4].id, domain[0], uuid.uuid4())
        booking.test_mode = False
        booking.status = "expired"
        booking.hold_until = now() - timedelta(seconds=1)
        payment = await db.scalar(
            select(Payment).where(Payment.booking_id == booking.id)
        )
        payment.provider = "stripe"
        payment.checkout_started_at = now() - timedelta(minutes=20)
        await db.commit()

    class Provider:
        async def checkout(self, p, b):
            assert p.id == payment.id and b.status == "expired"
            return {"id": "cs_recovered", "url": "https://example.com/test"}

        async def retrieve(self, p):
            return {
                "id": "pi_recovered",
                "status": "succeeded",
                "amount_received": payment.amount_minor,
                "currency": "rub",
                "latest_charge": "ch_recovered",
            }

    monkeypatch.setattr(settings, "TEST_MODE", False)
    monkeypatch.setattr(settings, "BILLING_LIVE_ENABLED", True)
    monkeypatch.setattr("app.billing.jobs.payment_provider", lambda *args: Provider())
    await reconcile_payments()
    async with AsyncSessionLocal() as db:
        p = await db.get(Payment, payment.id)
        assert p.status == "refund_pending" and p.checkout_id == "cs_recovered"
        assert (await db.get(Booking, booking.id)).status == "expired"


async def test_old_unknown_transfer_is_not_sent_twice(domain, monkeypatch):
    from app.billing.jobs import process_operations
    from app.billing.models import MoneyOperation, Payment
    from app.billing.service import reserve_booking

    async with AsyncSessionLocal() as db:
        booking = await reserve_booking(db, domain[4].id, domain[0], uuid.uuid4())
        booking.test_mode = False
        payment = await db.scalar(
            select(Payment).where(Payment.booking_id == booking.id)
        )
        db.add(
            MoneyOperation(
                payment_id=payment.id,
                kind="transfer",
                amount_minor=300000,
                attempts=1,
                created_at=now() - timedelta(days=2),
            )
        )
        await db.commit()
    monkeypatch.setattr(settings, "TEST_MODE", False)

    def must_not_call(*args):
        raise AssertionError("An uncertain old transfer must not be resubmitted")

    monkeypatch.setattr("app.billing.jobs.payment_provider", must_not_call)
    await process_operations()
    async with AsyncSessionLocal() as db:
        assert (await db.scalar(select(MoneyOperation))).status == "needs_review"


async def test_fee_reconciliation_preserves_settlement_currency(domain, monkeypatch):
    from app.billing.jobs import reconcile_processing_fees
    from app.billing.models import Payment
    from app.billing.service import reserve_booking

    async with AsyncSessionLocal() as db:
        booking = await reserve_booking(db, domain[4].id, domain[0], uuid.uuid4())
        payment = await db.scalar(
            select(Payment).where(Payment.booking_id == booking.id)
        )
        payment.provider = "stripe"
        payment.source_charge = "ch_test"
        await db.commit()

    async def charge_details(self, charge_id):
        assert charge_id == "ch_test"
        return {"balance_transaction": {"fee": 125, "currency": "eur"}}

    monkeypatch.setattr(settings, "TEST_MODE", False)
    monkeypatch.setattr(settings, "BILLING_LIVE_ENABLED", True)
    monkeypatch.setattr(
        "app.billing.providers.stripe_connect.StripeConnectProvider.charge_details",
        charge_details,
    )
    await reconcile_processing_fees()
    async with AsyncSessionLocal() as db:
        payment = await db.get(Payment, payment.id)
        assert payment.actual_fee_minor == 125 and payment.actual_fee_currency == "EUR"
