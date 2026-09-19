from decimal import ROUND_CEILING, ROUND_HALF_UP, Decimal

from sqlalchemy import select

from app.billing.errors import BillingError
from app.billing.models import PricingPolicy, PsychologistBilling
from app.core.settings import settings


def calculate_quote(hourly_net_minor, seconds, currency, rates):
    if hourly_net_minor <= 0 or seconds <= 0:
        raise BillingError("invalid_price", "Rate and duration must be positive")
    tax, platform, processor, fixed = rates
    if min(rates) < 0 or tax + platform + processor >= 10000:
        raise BillingError(
            "invalid_pricing_policy", "Total percentage must be below 100%"
        )
    net = int(
        (Decimal(hourly_net_minor) * Decimal(str(seconds)) / 3600).quantize(
            Decimal(1), rounding=ROUND_HALF_UP
        )
    )
    if net < 1:
        raise BillingError("invalid_price", "Session price must be at least one kopek")
    gross = int(
        (
            Decimal(net + fixed) * 10000 / (10000 - tax - platform - processor)
        ).to_integral_value(rounding=ROUND_CEILING)
    )

    def portion(bps):
        return int(
            (Decimal(gross) * bps / 10000).quantize(Decimal(1), rounding=ROUND_HALF_UP)
        )

    # Rounding is explicit; never reduce the promised net amount.
    while gross - portion(tax) - portion(platform) - portion(processor) - fixed < net:
        gross += 1
    return dict(
        hourly_net_minor=hourly_net_minor,
        duration_seconds=int(seconds),
        net_minor=net,
        amount_minor=gross,
        currency=currency,
        tax_minor=portion(tax),
        platform_fee_minor=portion(platform),
        processor_fee_estimate_minor=portion(processor) + fixed,
        rounding_minor=gross
        - net
        - portion(tax)
        - portion(platform)
        - portion(processor)
        - fixed,
        rates=dict(
            tax_bps=tax,
            platform_bps=platform,
            processor_bps=processor,
            processor_fixed_minor=fixed,
        ),
        rate_basis="gross",
        test_mode=settings.TEST_MODE,
    )


async def quote_slot(db, slot):
    profile = await db.get(PsychologistBilling, slot.psychologist_id)
    if not profile:
        raise BillingError("rate_not_set", "Psychologist must set an hourly rate")
    policy = await db.scalar(
        select(PricingPolicy)
        .where(PricingPolicy.test_mode == settings.TEST_MODE)
        .order_by(PricingPolicy.created_at.desc(), PricingPolicy.id.desc())
        .limit(1)
    )
    if policy:
        rates = (
            policy.tax_bps,
            policy.platform_bps,
            policy.processor_bps,
            policy.processor_fixed_minor,
        )
    elif settings.TEST_MODE:
        rates = (0, 0, 0, 0)
    else:
        rates = (
            settings.BILLING_TAX_BPS,
            settings.BILLING_PLATFORM_FEE_BPS,
            settings.BILLING_PROCESSOR_FEE_BPS,
            settings.BILLING_PROCESSOR_FIXED_MINOR,
        )
        if any(x is None for x in rates):
            raise BillingError(
                "pricing_not_configured",
                "Live tax and fee settings must be explicitly configured",
                status_code=503,
            )
    quote = calculate_quote(
        profile.hourly_net_minor,
        (slot.end_at - slot.start_at).total_seconds(),
        profile.currency,
        rates,
    )
    quote["policy_id"] = (
        str(policy.id)
        if policy
        else ("mock-zero-rates" if settings.TEST_MODE else "server-settings")
    )
    return quote
