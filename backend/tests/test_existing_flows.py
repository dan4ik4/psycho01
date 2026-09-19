"""Regression checks of existing account, assignment, calendar and rating features."""

import re
import secrets
from datetime import timedelta

import httpx
from app.auth.deps import get_jwt_strategy
from app.billing.models import now
from app.main import app


async def auth(user):
    return {"Authorization": "Bearer " + await get_jwt_strategy().write_token(user)}


async def test_registration_confirmation_and_real_login(monkeypatch):
    mail = []

    async def capture(**kwargs):
        mail.append(kwargs)

    monkeypatch.setattr("app.services.registration.send_email", capture)
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://test"
    ) as client:
        data = {"email": "newpatient@example.com", "password": secrets.token_urlsafe(32)}
        assert (
            await client.post("/api/v1/auth/preregister", json=data)
        ).status_code == 204
        assert len(mail) == 1
        code = re.search(r"\b\d{6}\b", mail[0]["text"])[0]
        bad_code = "111111" if code != "111111" else "222222"
        assert (
            await client.post(
                "/api/v1/auth/confirm",
                json={"email": data["email"], "otp_code": bad_code},
            )
        ).status_code == 400
        assert (
            await client.post(
                "/api/v1/auth/confirm", json={"email": data["email"], "otp_code": code}
            )
        ).status_code == 204
        login = await client.post(
            "/api/v1/auth/jwt/login",
            data={"username": data["email"], "password": data["password"]},
        )
        assert login.status_code == 200, login.text
        me = await client.get(
            "/api/v1/users/me",
            headers={"Authorization": "Bearer " + login.json()["access_token"]},
        )
        assert me.status_code == 200 and me.json()["email"] == data["email"]


async def test_profile_cannot_elevate_privileges_and_slot_validation(domain):
    patient, psy, _, _, slot = domain
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://test"
    ) as client:
        ph, sh = await auth(patient), await auth(psy)
        response = await client.patch(
            "/api/v1/users/me",
            headers=ph,
            json={
                "first_name": "Пациент",
                "is_superuser": True,
                "is_psychologist": True,
            },
        )
        assert (
            response.status_code == 200
            and not response.json()["is_superuser"]
            and not response.json()["is_psychologist"]
        )
        assert (await client.get("/api/v1/psychologists")).status_code == 200
        overlap = {
            "start_at": slot.start_at.isoformat(),
            "end_at": slot.end_at.isoformat(),
        }
        assert (
            await client.post("/api/v1/slots/create", headers=sh, json=overlap)
        ).status_code == 409
        assert (
            await client.post("/api/v1/slots/create", headers=ph, json=overlap)
        ).status_code == 403
        future = now() + timedelta(days=2)
        invalid = {
            "start_at": future.replace(tzinfo=None).isoformat(),
            "end_at": (future + timedelta(hours=1)).isoformat(),
        }
        assert (
            await client.post("/api/v1/slots/create", headers=sh, json=invalid)
        ).status_code == 422


async def test_assignment_request_accept_finish_and_rating_guard(domain):
    _, psy, patient, _, _ = domain
    ph, sh = await auth(patient), await auth(psy)
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://test"
    ) as client:
        response = await client.post(
            "/api/v1/patient-assignments/request",
            headers=ph,
            json={
                "psychologist_id": str(psy.id),
                "comment": "Хочу начать работу с психологом",
            },
        )
        assert response.status_code == 201, response.text
        assignment_id = response.json()["id"]
        assert (
            await client.post(
                f"/api/v1/patient-assignments/{assignment_id}/accept", headers=ph
            )
        ).status_code == 403
        assert (
            await client.post(
                f"/api/v1/patient-assignments/{assignment_id}/accept", headers=sh
            )
        ).status_code == 200
        assert (
            await client.put(
                f"/api/v1/psychologists_rating/{psy.id}/rating",
                headers=ph,
                json={"rating": 5},
            )
        ).status_code == 403
        assert (
            await client.post(
                f"/api/v1/patient-assignments/{assignment_id}/finish",
                headers=ph,
                json={"comment": "Завершение локальной проверки"},
            )
        ).status_code == 200
