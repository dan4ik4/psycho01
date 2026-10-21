"""Client-facing contracts, privacy and password reset, with no external sends."""

import io
import re
import uuid
from datetime import timedelta
from urllib.parse import parse_qs, urlsplit

import httpx
import jwt
import pytest
from app.ai.services.ai_care_plan import (
    activate_care_plan_version,
    create_care_plan,
    pause_care_plan,
)
from app.auth.deps import get_jwt_strategy
from app.billing.models import Payment, PricingPolicy, PsychologistBilling, now
from app.billing.service import confirm_payment, reserve_booking
from app.core.settings import settings
from app.db.session import AsyncSessionLocal
from app.main import app
from app.models.user import User
from PIL import Image
from sqlalchemy import select


async def headers(user):
    return {"Authorization": "Bearer " + await get_jwt_strategy().write_token(user)}


def client():
    return httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://test"
    )


async def test_reset_link_expiry_replay_and_password_rules(domain, monkeypatch):
    sent = []

    async def capture(**kwargs):
        sent.append(kwargs)

    monkeypatch.setattr("app.auth.deps.send_email", capture)
    monkeypatch.setattr(settings, "PASSWORD_RESET_URL", "oakle://reset-password")
    async with client() as http:
        response = await http.post(
            "/api/v1/auth/forgot-password", json={"email": domain[0].email}
        )
        assert response.status_code == 202 and len(sent) == 1
        link = re.search(r"oakle://\S+", sent[0]["text"])[0]
        parts = urlsplit(link)
        assert parts.netloc == "reset-password"
        token = parse_qs(parts.query)["token"][0]
        payload = jwt.decode(token, options={"verify_signature": False})
        assert 3500 <= payload["exp"] - now().timestamp() <= 3600
        expired = jwt.encode(
            {**payload, "exp": 0}, settings.JWT_SECRET, algorithm="HS256"
        )
        for bad in [expired, "invalid"]:
            result = await http.post(
                "/api/v1/auth/reset-password",
                json={"token": bad, "password": "new-password11"},
            )
            assert result.status_code == 400
        short = await http.post(
            "/api/v1/auth/reset-password", json={"token": token, "password": "short"}
        )
        assert short.status_code == 400
        reset = await http.post(
            "/api/v1/auth/reset-password",
            json={"token": token, "password": "new-password11"},
        )
        assert reset.status_code == 200, reset.text
        replay = await http.post(
            "/api/v1/auth/reset-password",
            json={"token": token, "password": "other-password11"},
        )
        assert replay.status_code == 400
        login = await http.post(
            "/api/v1/auth/jwt/login",
            data={"username": domain[0].email, "password": "new-password11"},
        )
        assert login.status_code == 200


async def test_photos_upload_replace_delete_public_and_permissions(
    domain, monkeypatch, tmp_path
):
    monkeypatch.setattr(settings, "AVATAR_STORAGE_DIR", str(tmp_path))
    monkeypatch.setattr(settings, "PUBLIC_BASE_URL", "http://test")
    image = io.BytesIO()
    Image.new("RGB", (1400, 500), "purple").save(image, format="PNG")
    photo = image.getvalue()
    async with client() as http:
        path = "/api/v1/psychologists/me/photo"
        assert (
            await http.post(
                path,
                headers=await headers(domain[0]),
                files={"file": ("x.png", photo, "image/png")},
            )
        ).status_code == 403
        sh = await headers(domain[1])
        first = await http.post(
            path, headers=sh, files={"file": ("x.png", photo, "image/png")}
        )
        assert first.status_code == 200, first.text
        url = first.json()["avatar_url"]
        content = await http.get(url)
        assert (
            content.status_code == 200
            and content.headers["content-type"] == "image/webp"
        )
        with Image.open(io.BytesIO(content.content)) as output:
            assert max(output.size) <= 1024 and not output.getexif()
        listing = (await http.get("/api/v1/psychologists")).json()
        assert listing[0]["avatar_url"] == url
        assert (await http.get("/api/v1/psychologists/me", headers=sh)).json()[
            "avatar_url"
        ] == url
        second = await http.post(
            path, headers=sh, files={"file": ("x.png", photo, "image/png")}
        )
        assert second.status_code == 200 and second.json()["avatar_url"] != url
        assert (await http.get(url)).status_code == 404
        deleted = await http.delete(path, headers=sh)
        assert deleted.status_code == 200 and deleted.json()["avatar_url"] is None
        assert (await http.get(second.json()["avatar_url"])).status_code == 404
        assert (await http.delete(path, headers=sh)).status_code == 200
        assert not list(tmp_path.iterdir())


@pytest.mark.parametrize(
    "data,content_type,status",
    [
        (b"<svg/>", "image/svg+xml", 415),
        (b"not an image", "image/png", 422),
        (b"x" * (5 * 1024 * 1024 + 1), "image/jpeg", 413),
    ],
)
async def test_invalid_photos(domain, data, content_type, status):
    async with client() as http:
        result = await http.post(
            "/api/v1/psychologists/me/photo",
            headers=await headers(domain[1]),
            files={"file": ("image", data, content_type)},
        )
        assert result.status_code == status


async def test_catalog_usd_cents_fees_and_missing_rate(domain):
    async with AsyncSessionLocal() as db:
        db.add(
            PricingPolicy(
                test_mode=True,
                currency="USD",
                tax_bps=0,
                platform_bps=1000,
                processor_bps=0,
                processor_fixed_minor=0,
            )
        )
        await db.commit()
    async with client() as http:
        sh = await headers(domain[1])
        saved = await http.patch(
            "/api/v1/billing/psychologist/me",
            headers=sh,
            json={"hourly_net_minor": 10000},
        )
        assert saved.status_code == 200 and saved.json()["currency"] == "USD"
        assert (await http.get("/api/v1/billing/psychologist/me", headers=sh)).json()[
            "hourly_net_minor"
        ] == 10000
        item = (await http.get("/api/v1/psychologists")).json()[0]
        assert item["hourly_net_minor"] == 10000 and item["hourly_price_minor"] > 10000
        quote = await http.get(
            f"/api/v1/billing/slots/{domain[4].id}/quote",
            headers=await headers(domain[0]),
        )
        assert (
            quote.status_code == 200
            and quote.json()["amount_minor"] == item["hourly_price_minor"]
        )
        summary = (await http.get("/api/v1/billing/me", headers=sh)).json()
        assert (
            summary["subscription_price_minor"] == 900 and summary["currency"] == "USD"
        )
    async with AsyncSessionLocal() as db:
        profile = await db.get(PsychologistBilling, domain[1].id)
        profile.hourly_net_minor = None
        await db.commit()
    async with client() as http:
        item = (await http.get("/api/v1/psychologists")).json()[0]
        assert item["hourly_net_minor"] is None and item["hourly_price_minor"] is None


async def test_calendar_names_reservation_and_access(domain):
    patient, psy, stranger, _assignment, slot = domain
    async with AsyncSessionLocal() as db:
        p = await db.get(User, patient.id)
        p.first_name, p.last_name = "Test", "Patient"
        other = await db.get(User, stranger.id)
        other.is_psychologist = True
        await db.commit()
    async with client() as http:
        sh = await headers(psy)
        own = await http.get("/api/v1/patient-assignments/active", headers=sh)
        assert (
            own.status_code == 200 and own.json()[0]["patient"]["first_name"] == "Test"
        )
        assert set(own.json()[0]["patient"]) == {"id", "first_name", "last_name"}
        assert (
            await http.get(
                "/api/v1/patient-assignments/active", headers=await headers(stranger)
            )
        ).json() == []
        assert (await http.get("/api/v1/slots/my", headers=sh)).json()[0][
            "status"
        ] == "free"
    async with AsyncSessionLocal() as db:
        booking = await reserve_booking(db, slot.id, patient, uuid.uuid4())
        booking_id = booking.id
    async with client() as http:
        held = (await http.get("/api/v1/slots/my", headers=await headers(psy))).json()[
            0
        ]
        assert held["status"] == "reserved" and held["patient"]["id"] == str(patient.id)
    async with AsyncSessionLocal() as db:
        payment = await db.scalar(
            select(Payment).where(Payment.booking_id == booking_id)
        )
        await confirm_payment(
            db,
            payment.id,
            external_id="mock-test",
            amount_minor=payment.amount_minor,
            currency=payment.currency,
        )
        await db.commit()
    async with client() as http:
        doc_slot = (
            await http.get("/api/v1/slots/my", headers=await headers(psy))
        ).json()[0]
        patient_slot = (
            await http.get("/api/v1/slots/booked", headers=await headers(patient))
        ).json()[0]
        assert doc_slot["status"] == patient_slot["status"] == "booked"
        assert doc_slot["patient"] == patient_slot["patient"]
        assert (
            await http.get("/api/v1/slots/my", headers=await headers(stranger))
        ).json() == []
        assert (
            await http.get("/api/v1/slots/booked", headers=await headers(psy))
        ).status_code == 403


async def test_free_recommendations_hide_instructions_and_respect_activation(domain):
    patient, psy, stranger, assignment, _ = domain
    async with AsyncSessionLocal() as db:
        _, version = await create_care_plan(
            db, assignment.id, psy.id, "PRIVATE", "Patient text"
        )
    path = f"/api/v1/ai/care-plans/{assignment.id}/patient"
    async with client() as http:
        assert (await http.get(path, headers=await headers(patient))).status_code == 409
    async with AsyncSessionLocal() as db:
        await activate_care_plan_version(db, assignment.id, psy.id, version.id)
    async with client() as http:
        result = await http.get(path, headers=await headers(patient))
        assert (
            result.status_code == 200
            and result.json()["patient_recommendations"] == "Patient text"
        )
        assert "PRIVATE" not in result.text and "instructions_for_ai" not in result.text
        assert (
            await http.get(path, headers=await headers(stranger))
        ).status_code == 403
        assert (await http.get(path, headers=await headers(psy))).status_code == 403
        guided = await http.post(
            "/api/v1/ai/conversations",
            headers=await headers(patient),
            json={"name": "Guided", "mode": "guided"},
        )
        assert guided.status_code == 403
    async with AsyncSessionLocal() as db:
        await pause_care_plan(db, assignment.id, psy.id, None)
    async with client() as http:
        assert (await http.get(path, headers=await headers(patient))).status_code == 409


async def test_schedule_datetime_errors_creation_removal_and_roles(domain):

    start = now() + timedelta(days=2)
    body = {
        "start_at": start.isoformat(),
        "end_at": (start + timedelta(minutes=30)).isoformat(),
    }
    async with client() as http:
        sh = await headers(domain[1])
        patient_headers = await headers(domain[0])
        denied = await http.get("/api/v1/slots/my", headers=patient_headers)
        assert (
            denied.status_code == 403
            and denied.json()["detail"] == "Only psychologists can view their slots"
        )
        invalid = await http.post(
            "/api/v1/slots/create",
            headers=sh,
            json={**body, "start_at": start.replace(tzinfo=None).isoformat()},
        )
        assert invalid.status_code == 422 and invalid.json()["detail"][0]["loc"] == [
            "body",
            "start_at",
        ]
        assert (
            await http.post("/api/v1/slots/create", headers=patient_headers, json=body)
        ).status_code == 403
        short = {**body, "end_at": (start + timedelta(minutes=14)).isoformat()}
        assert (
            await http.post("/api/v1/slots/create", headers=sh, json=short)
        ).status_code == 400
        past = {
            "start_at": (start - timedelta(days=4)).isoformat(),
            "end_at": (start - timedelta(days=3)).isoformat(),
        }
        assert (
            await http.post("/api/v1/slots/create", headers=sh, json=past)
        ).status_code == 400
        created = await http.post("/api/v1/slots/create", headers=sh, json=body)
        assert created.status_code == 200, created.text
        slot_id = created.json()["id"]
        assert (
            await http.post("/api/v1/slots/create", headers=sh, json=body)
        ).status_code == 409
        assert slot_id in [
            s["id"] for s in (await http.get("/api/v1/slots/my", headers=sh)).json()
        ]
        removed = await http.post(
            f"/api/v1/slots/{slot_id}/remove", headers=sh, json={}
        )
        assert removed.status_code == 200, removed.text
        assert slot_id not in [
            s["id"] for s in (await http.get("/api/v1/slots/my", headers=sh)).json()
        ]
