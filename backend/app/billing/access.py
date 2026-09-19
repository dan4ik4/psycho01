from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from sqlalchemy import select, text
from sqlalchemy.dialects.postgresql import insert

from app.billing.errors import BillingError
from app.billing.models import AiUsage, Subscription, now
from app.core.settings import settings


async def lock_account(db, user_id):
    # Separate from user row locks: a consistent lock for all chats and subscription changes.
    await db.execute(
        text("SELECT pg_advisory_xact_lock(hashtextextended(:key, 0))"),
        {"key": f"billing:{user_id}"},
    )


def usage_period():
    local = now().astimezone(ZoneInfo(settings.BILLING_TIMEZONE))
    reset = datetime.combine(
        local.date() + timedelta(days=1), datetime.min.time(), tzinfo=local.tzinfo
    )
    return local.date(), reset.astimezone(timezone.utc)


async def paid_access(db, user_id):
    sub = await db.scalar(
        select(Subscription).where(
            Subscription.user_id == user_id,
            Subscription.test_mode == settings.TEST_MODE,
        )
    )
    return sub if sub and sub.expires_at and sub.expires_at > now() else None


async def require_paid(db, user_id):
    if not await paid_access(db, user_id):
        raise BillingError(
            "subscription_required",
            "A paid AI subscription is required",
            status_code=403,
        )


async def quota_for_message(db, user_id):
    # Caller holds lock_account throughout generation. Rollback/crash cannot spend quota.
    if await paid_access(db, user_id):
        return None
    day, reset = usage_period()
    await db.execute(
        insert(AiUsage)
        .values(user_id=user_id, day=day, test_mode=settings.TEST_MODE, used=0)
        .on_conflict_do_nothing()
    )
    usage = await db.get(
        AiUsage, (user_id, day, settings.TEST_MODE), with_for_update=True
    )
    if usage.used >= settings.AI_FREE_DAILY_LIMIT:
        raise BillingError(
            "daily_limit_exceeded",
            "Free AI daily limit reached",
            status_code=429,
            resets_at=reset.isoformat(),
        )
    return usage


async def access_summary(db, user_id):
    sub = await paid_access(db, user_id)
    day, reset = usage_period()
    usage = await db.get(AiUsage, (user_id, day, settings.TEST_MODE))
    return dict(
        test_mode=settings.TEST_MODE,
        plan="paid" if sub else "free",
        expires_at=sub.expires_at if sub else None,
        remaining_messages=None
        if sub
        else max(0, settings.AI_FREE_DAILY_LIMIT - (usage.used if usage else 0)),
        resets_at=reset,
        guided_subscription_access=bool(sub),
        subscription_price_minor=settings.SUBSCRIPTION_PRICE_MINOR,
        currency=settings.BILLING_CURRENCY,
        subscription_days=settings.SUBSCRIPTION_DAYS,
    )
