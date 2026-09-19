"""HTTP contracts, authorization and end-to-end mock journeys on real PostgreSQL."""

import uuid

import httpx
import pytest
from sqlalchemy import select

from app.auth.deps import get_jwt_strategy
from app.billing.jobs import process_operations
from app.billing.models import MoneyOperation, PricingPolicy
from app.db.session import AsyncSessionLocal
from app.main import app


async def headers(user):
    return {"Authorization": "Bearer " + await get_jwt_strategy().write_token(user)}


async def test_patient_payment_journey_and_permissions(domain):
    patient, psy, stranger, _, slot = domain
    ph, sh, oh = await headers(patient), await headers(psy), await headers(stranger)
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://test"
    ) as client:
        assert (await client.get("/api/v1/billing/me")).status_code == 401
        assert (await client.get("/api/v1/users/me", headers=ph)).status_code == 200
        slots = await client.get("/api/v1/slots/available", headers=ph)
        assert slots.status_code == 200 and slots.json()[0]["id"] == str(slot.id)
        assert (
            await client.patch(
                "/api/v1/billing/psychologist/me",
                headers=ph,
                json={"hourly_net_minor": 100},
            )
        ).status_code == 403
        assert (
            await client.get("/api/v1/billing/admin/operations", headers=ph)
        ).status_code == 403
        response = await client.post(
            f"/api/v1/slots/{slot.id}/book",
            headers=ph,
            json={"request_id": str(uuid.uuid4())},
        )
        assert response.status_code == 200, response.text
        booking = response.json()
        assert (
            booking["status"] == "pending"
            and booking["quote"]["amount_minor"] == 300000
        )
        path = f"/api/v1/billing/bookings/{booking['id']}"
        assert (await client.get(path, headers=oh)).status_code == 404
        assert (await client.post(path + "/checkout", headers=sh)).status_code == 403
        assert (await client.post(path + "/checkout", headers=ph)).status_code == 200
        paid = await client.post(
            f"/api/v1/billing/mock/bookings/{booking['id']}/pay",
            headers=ph,
            json={"outcome": "success"},
        )
        assert paid.status_code == 200 and paid.json()["status"] == "confirmed", (
            paid.text
        )
        assert len((await client.get("/api/v1/slots/booked", headers=ph)).json()) == 1
        assert (await client.post(path + "/cancel", headers=ph)).json()[
            "payment_status"
        ] == "refund_pending"
        await process_operations()
        assert (await client.get(path, headers=ph)).json()[
            "payment_status"
        ] == "refunded"


async def test_ai_http_quota_and_subscription(domain):
    ph = await headers(domain[0])
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://test", headers=ph
    ) as client:
        response = await client.post(
            "/api/v1/ai/conversations", json={"name": "API", "mode": "self_help"}
        )
        assert response.status_code == 201, response.text
        path = f"/api/v1/ai/conversations/{response.json()['id']}"
        for _ in range(3):
            sent = await client.post(
                path + "/messages",
                json={"content": "Проверка", "request_id": str(uuid.uuid4())},
            )
            assert (
                sent.status_code == 201 and sent.json()["assistant_message"]["content"]
            ), sent.text
        limited = await client.post(
            path + "/messages",
            json={"content": "Четвёртое", "request_id": str(uuid.uuid4())},
        )
        assert (
            limited.status_code == 429
            and limited.json()["code"] == "daily_limit_exceeded"
        )
        bought = await client.post(
            "/api/v1/billing/mock/subscription", json={"request_id": str(uuid.uuid4())}
        )
        assert bought.status_code == 200 and bought.json()["plan"] == "paid"
        assert (
            await client.post(
                path + "/messages",
                json={"content": "Ещё", "request_id": str(uuid.uuid4())},
            )
        ).status_code == 201
        assert (await client.delete("/api/v1/billing/mock/subscription")).json()[
            "plan"
        ] == "free"
        assert len((await client.get(path)).json()["messages"]) == 8


async def test_full_refund_includes_all_fees_and_price_is_frozen(domain):
    patient, psy, _, _, slot = domain
    async with AsyncSessionLocal() as db:
        db.add(
            PricingPolicy(
                test_mode=True,
                tax_bps=1000,
                platform_bps=1500,
                processor_bps=300,
                processor_fixed_minor=30,
            )
        )
        await db.commit()
    ph = await headers(patient)
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://test", headers=ph
    ) as client:
        booking = (
            await client.post(
                f"/api/v1/slots/{slot.id}/book", json={"request_id": str(uuid.uuid4())}
            )
        ).json()
        assert booking["quote"]["amount_minor"] > 300000
        await client.patch(
            "/api/v1/billing/psychologist/me",
            headers=await headers(psy),
            json={"hourly_net_minor": 600000},
        )
        paid = await client.post(
            f"/api/v1/billing/mock/bookings/{booking['id']}/pay",
            json={"outcome": "success"},
        )
        assert paid.json()["quote"] == booking["quote"]
        await client.post(f"/api/v1/billing/bookings/{booking['id']}/cancel")
    await process_operations()
    async with AsyncSessionLocal() as db:
        refund = await db.scalar(select(MoneyOperation))
        assert (
            refund.amount_minor == booking["quote"]["amount_minor"]
            and refund.status == "succeeded"
        )


async def test_admin_mock_finish_and_monthly_earnings(domain):
    patient, psy, admin, _, slot = domain
    async with AsyncSessionLocal() as db:
        db.add(admin)
        admin.is_superuser = True
        await db.commit()
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://test"
    ) as client:
        ph = await headers(patient)
        booking = (
            await client.post(
                f"/api/v1/slots/{slot.id}/book",
                headers=ph,
                json={"request_id": str(uuid.uuid4())},
            )
        ).json()
        await client.post(
            f"/api/v1/billing/mock/bookings/{booking['id']}/pay",
            headers=ph,
            json={"outcome": "success"},
        )
        finish_path = f"/api/v1/billing/mock/bookings/{booking['id']}/finish"
        assert (
            await client.post(
                finish_path,
                headers=ph,
                json={"patient_present": False, "psychologist_present": True},
            )
        ).status_code == 403
        finished = await client.post(
            finish_path,
            headers=await headers(admin),
            json={"patient_present": False, "psychologist_present": True},
        )
        assert (
            finished.status_code == 200
            and finished.json()["outcome"] == "patient_absent"
        ), finished.text
        assert (
            await client.post(
                "/api/v1/billing/mock/run-jobs", headers=await headers(admin)
            )
        ).status_code == 200
        earnings = await client.get(
            "/api/v1/billing/psychologist/earnings", headers=await headers(psy)
        )
        assert (
            earnings.status_code == 200
            and earnings.json()["totals"][0]["earned_net_minor"] == 300000
        )
        assert earnings.json()["totals"][0]["transferred_minor"] == 300000


@pytest.mark.parametrize("path", ["/docs", "/openapi.json", "/api/v1/health"])
async def test_public_routes(path):
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://test"
    ) as client:
        assert (await client.get(path)).status_code == 200


@pytest.mark.parametrize("test_mode", [True, False])
async def test_no_demo_frontend_in_any_mode(monkeypatch, test_mode):
    from app.core.settings import settings

    monkeypatch.setattr(settings, "TEST_MODE", test_mode)
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://test"
    ) as client:
        for path in ("/", "/static/demo.html"):
            assert (await client.get(path)).status_code == 404
