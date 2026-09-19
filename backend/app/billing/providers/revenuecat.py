import httpx

from app.billing.errors import BillingError
from app.core.settings import settings


class RevenueCatProvider:
    async def subscriber(self, user_id):
        if not settings.BILLING_LIVE_ENABLED or not settings.REVENUECAT_SECRET_KEY:
            raise BillingError(
                "live_billing_disabled",
                "RevenueCat requires explicit live configuration",
                status_code=503,
            )
        try:
            async with httpx.AsyncClient(timeout=20) as client:
                response = await client.get(
                    f"https://api.revenuecat.com/v1/subscribers/{user_id}",
                    headers={
                        "Authorization": f"Bearer {settings.REVENUECAT_SECRET_KEY}"
                    },
                )
                response.raise_for_status()
                return response.json()["subscriber"]
        except (httpx.HTTPError, ValueError, KeyError) as error:
            raise BillingError(
                "provider_unavailable",
                "Subscription provider is unavailable",
                status_code=502,
            ) from error
