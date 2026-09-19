from datetime import datetime, timedelta

from sqlalchemy import select

from app.billing.access import access_summary, lock_account
from app.billing.models import Subscription, SubscriptionPurchase, now
from app.billing.providers.revenuecat import RevenueCatProvider
from app.core.errors import NotFoundError
from app.core.settings import settings


async def mock_purchase(db, user_id, request_id):
    if not settings.TEST_MODE:
        raise NotFoundError("Not found")
    await lock_account(db, user_id)
    existing = await db.scalar(
        select(SubscriptionPurchase).where(
            SubscriptionPurchase.user_id == user_id,
            SubscriptionPurchase.request_id == request_id,
        )
    )
    if existing:
        return await access_summary(db, user_id)
    sub = await db.scalar(
        select(Subscription).where(
            Subscription.user_id == user_id, Subscription.test_mode.is_(True)
        )
    )
    if not sub:
        sub = Subscription(user_id=user_id, test_mode=True, provider="mock")
        db.add(sub)
    sub.expires_at = max(sub.expires_at or now(), now()) + timedelta(
        days=settings.SUBSCRIPTION_DAYS
    )
    sub.updated_at = now()
    db.add(
        SubscriptionPurchase(
            user_id=user_id,
            request_id=request_id,
            amount_minor=settings.SUBSCRIPTION_PRICE_MINOR,
            currency=settings.BILLING_CURRENCY,
            expires_at=sub.expires_at,
        )
    )
    await db.commit()
    return await access_summary(db, user_id)


async def sync_subscription(db, user_id, *, commit=True):
    if settings.TEST_MODE:
        return await access_summary(db, user_id)
    await lock_account(db, user_id)
    # Serialize subscriber refreshes; always request authoritative current state.
    data = await RevenueCatProvider().subscriber(user_id)
    entitlement = data.get("entitlements", {}).get(settings.REVENUECAT_ENTITLEMENT)
    expires = None
    will_renew = False
    if entitlement:
        product = data.get("subscriptions", {}).get(
            entitlement.get("product_identifier"), {}
        )
        if product and not product.get("is_sandbox", True):
            raw_expiration = entitlement.get("expires_date")
            if raw_expiration:
                expires = datetime.fromisoformat(raw_expiration.replace("Z", "+00:00"))
            # This product is recurring; perpetual/unrecognised grants are not accepted silently.
            grace = product.get("grace_period_expires_date")
            if grace:
                grace_date = datetime.fromisoformat(grace.replace("Z", "+00:00"))
                expires = max(expires, grace_date) if expires else grace_date
            will_renew = not product.get("unsubscribe_detected_at")
    sub = await db.scalar(
        select(Subscription).where(
            Subscription.user_id == user_id, Subscription.test_mode.is_(False)
        )
    )
    if not sub:
        sub = Subscription(user_id=user_id, test_mode=False, provider="revenuecat")
        db.add(sub)
    sub.expires_at, sub.will_renew, sub.updated_at = expires, will_renew, now()
    if commit:
        await db.commit()
    else:
        await db.flush()
    return await access_summary(db, user_id)
