from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.billing.errors import BillingError
from app.billing.models import PsychologistBilling
from app.billing.pricing import calculate_quote, pricing_rates
from app.core.settings import settings
from app.models.user import User
from app.schemas.psychologists import PsychologistListOut


async def get_psychologists(db: AsyncSession) -> list[PsychologistListOut]:
    rows = (
        await db.execute(
            select(User, PsychologistBilling)
            .outerjoin(PsychologistBilling, PsychologistBilling.user_id == User.id)
            .where(User.is_psychologist.is_(True), User.is_active.is_(True))
            .order_by(
                User.last_name.asc().nulls_last(),
                User.first_name.asc().nulls_last(),
                User.id.asc(),
            )
        )
    ).all()
    rates_by_currency = {}
    result = []
    for user, billing in rows:
        currency = billing.currency if billing else settings.BILLING_CURRENCY
        rate = billing.hourly_net_minor if billing else None
        price = None
        if rate is not None:
            if currency not in rates_by_currency:
                try:
                    rates_by_currency[currency] = (await pricing_rates(db, currency))[0]
                except BillingError as error:
                    if error.code != "pricing_not_configured":
                        raise
                    rates_by_currency[currency] = None
            rates = rates_by_currency[currency]
            if rates is not None:
                price = calculate_quote(rate, 3600, currency, rates)["amount_minor"]
        result.append(
            PsychologistListOut(
                id=user.id,
                first_name=user.first_name,
                last_name=user.last_name,
                specialization=user.specialization,
                bio=user.bio,
                experience_years=user.experience_years,
                average_rating=user.average_rating,
                ratings_count=user.ratings_count,
                avatar_url=user.avatar_url,
                hourly_net_minor=rate,
                currency=currency,
                hourly_price_minor=price,
            )
        )
    return result
