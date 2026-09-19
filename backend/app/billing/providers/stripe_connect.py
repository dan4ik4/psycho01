import hashlib
import hmac
import json
import time

import httpx

from app.billing.errors import BillingError
from app.core.settings import settings


def verify_stripe_event(body, signature):
    if not settings.STRIPE_WEBHOOK_SECRET:
        raise BillingError(
            "provider_not_configured",
            "Stripe webhook is not configured",
            status_code=503,
        )
    try:
        parts = [p.split("=", 1) for p in signature.split(",")]
        timestamp = next(v for k, v in parts if k == "t")
        expected = hmac.new(
            settings.STRIPE_WEBHOOK_SECRET.encode(),
            timestamp.encode() + b"." + body,
            hashlib.sha256,
        ).hexdigest()
        valid = any(hmac.compare_digest(expected, v) for k, v in parts if k == "v1")
        if not valid or abs(time.time() - int(timestamp)) > 300:
            raise ValueError()
        event = json.loads(body)
        if not isinstance(event, dict):
            raise ValueError()
        return event
    except (ValueError, StopIteration, TypeError):
        raise BillingError(
            "invalid_signature", "Invalid Stripe webhook signature", status_code=400
        )


class StripeConnectProvider:
    async def request(self, method, path, *, data=None, key=None, params=None):
        if not settings.BILLING_LIVE_ENABLED or not settings.STRIPE_SECRET_KEY:
            raise BillingError(
                "live_billing_disabled",
                "Live payments require explicit configuration",
                status_code=503,
            )
        headers = {"Authorization": f"Bearer {settings.STRIPE_SECRET_KEY}"}
        if key:
            headers["Idempotency-Key"] = str(key)
        try:
            async with httpx.AsyncClient(timeout=20) as client:
                response = await client.request(
                    method,
                    "https://api.stripe.com/v1/" + path,
                    data=data,
                    params=params,
                    headers=headers,
                )
                response.raise_for_status()
                return response.json()
        except (httpx.HTTPError, ValueError) as error:
            # Do not leak API keys or provider payloads through exception messages.
            raise BillingError(
                "provider_unavailable",
                "Payment provider request failed; retry or reconcile",
                status_code=502,
            ) from error

    async def checkout(self, payment, booking):
        return await self.request(
            "POST",
            "checkout/sessions",
            key=f"checkout:{payment.id}",
            data={
                "mode": "payment",
                "payment_method_types[0]": "card",
                "line_items[0][price_data][currency]": payment.currency.lower(),
                "line_items[0][price_data][unit_amount]": str(payment.amount_minor),
                "line_items[0][price_data][product_data][name]": "Psychologist consultation",
                "line_items[0][quantity]": "1",
                "metadata[payment_id]": str(payment.id),
                "payment_intent_data[metadata][payment_id]": str(payment.id),
                "payment_intent_data[transfer_group]": f"booking_{booking.id}",
                "success_url": settings.FRONTEND_URL
                + "/payment/success?session_id={CHECKOUT_SESSION_ID}",
                "cancel_url": settings.FRONTEND_URL + "/payment/cancel",
            },
        )

    async def retrieve(self, payment):
        if payment.external_id:
            return await self.request("GET", f"payment_intents/{payment.external_id}")
        if payment.checkout_id:
            session = await self.request(
                "GET", f"checkout/sessions/{payment.checkout_id}"
            )
            if session.get("payment_intent"):
                return await self.request(
                    "GET", f"payment_intents/{session['payment_intent']}"
                )
        return None

    async def refund(self, payment, operation):
        if operation.external_id:
            return await self.request("GET", f"refunds/{operation.external_id}")
        return await self.request(
            "POST",
            "refunds",
            key=f"refund:{operation.id}",
            data={
                "payment_intent": payment.external_id,
                "amount": str(operation.amount_minor),
                "metadata[operation_id]": str(operation.id),
            },
        )

    async def transfer(self, payment, operation):
        if operation.external_id:
            result = await self.request("GET", f"transfers/{operation.external_id}")
            return {
                "id": result["id"],
                "status": "failed" if result.get("reversed") else "succeeded",
            }
        if not payment.destination or not payment.source_charge:
            raise BillingError(
                "transfer_not_ready", "Charge or connected account is not ready"
            )
        result = await self.request(
            "POST",
            "transfers",
            key=f"transfer:{operation.id}",
            data={
                "amount": str(operation.amount_minor),
                "currency": payment.currency.lower(),
                "destination": payment.destination,
                "source_transaction": payment.source_charge,
                "transfer_group": f"booking_{payment.booking_id}",
                "metadata[operation_id]": str(operation.id),
            },
        )
        return {"id": result["id"], "status": "succeeded"}

    async def account(self, account_id):
        return await self.request("GET", f"accounts/{account_id}")

    async def charge_details(self, charge_id):
        return await self.request(
            "GET", f"charges/{charge_id}", params={"expand[]": "balance_transaction"}
        )
