"""Independent provider switches; real SDK calls are replaced by local fakes."""

import itertools
import re
import secrets
from types import SimpleNamespace

import httpx
import pytest

from app.ai.providers.chat import generate_ai_reply
from app.billing.providers import payment_provider
from app.billing.providers.mock import MockPaymentProvider
from app.core.mailer import send_email
from app.core.settings import Settings, settings
from app.main import app
from app.services.agora import generate_agora_token

FLAGS = ("EMAIL_TEST_MODE", "AI_TEST_MODE", "BILLING_TEST_MODE", "AGORA_TEST_MODE")


@pytest.mark.parametrize("legacy", [True, False])
def test_legacy_defaults_and_explicit_overrides(monkeypatch, legacy):
    for flag in FLAGS:
        monkeypatch.delenv(flag, raising=False)
    defaults = Settings(_env_file=None, TEST_MODE=legacy)
    assert all(getattr(defaults, flag) is legacy for flag in FLAGS)
    for flag in FLAGS:
        monkeypatch.setenv(flag, str(not legacy).lower())
        mixed = Settings(_env_file=None, TEST_MODE=legacy)
        assert getattr(mixed, flag) is not legacy
        assert all(getattr(mixed, other) is legacy for other in FLAGS if other != flag)
        monkeypatch.delenv(flag)


@pytest.mark.parametrize("modes", list(itertools.product([False, True], repeat=4)))
async def test_provider_modes_are_independent(monkeypatch, modes):
    for flag, value in zip(FLAGS, modes):
        monkeypatch.setattr(settings, flag, value)
    # An old global true must not override a service explicitly set to false.
    monkeypatch.setattr(settings, "TEST_MODE", True)
    monkeypatch.setattr(settings, "OPENAI_API_KEY", "local-test-key")
    monkeypatch.setattr(settings, "RESEND_API_KEY", "local-test-key")
    calls = []

    def fake_mail(params):
        calls.append("email")
        return {"id": "local-email"}

    async def fake_ai(**kwargs):
        calls.append("ai")
        return SimpleNamespace(status="completed", output_text="Local SDK response")

    def fake_agora(*args):
        calls.append("agora")
        return "local-sdk-token"

    monkeypatch.setattr("app.core.mailer.resend.Emails.send", fake_mail)
    monkeypatch.setattr("app.ai.providers.chat.get_openai_client", lambda: SimpleNamespace(
        responses=SimpleNamespace(create=fake_ai)
    ))
    monkeypatch.setattr("app.services.agora.RtcTokenBuilder.buildTokenWithUid", fake_agora)
    await send_email("test@example.com", "Test", "Test")
    reply = await generate_ai_reply([{"role": "user", "content": "Hello"}])
    token = generate_agora_token("room", 1, 2000000000)
    assert ("email" in calls) is not modes[0]
    assert ("ai" in calls) is not modes[1]
    assert (reply == "Local SDK response") is not modes[1]
    assert isinstance(payment_provider(), MockPaymentProvider) is modes[2]
    assert ("agora" in calls) is not modes[3]
    assert (token == "local-sdk-token") is not modes[3]


async def test_real_email_registration_while_other_services_stay_mock(monkeypatch):
    monkeypatch.setattr(settings, "EMAIL_TEST_MODE", False)
    monkeypatch.setattr(settings, "RESEND_API_KEY", "local-test-key")
    for flag in FLAGS[1:]:
        monkeypatch.setattr(settings, flag, True)
    sent = []
    monkeypatch.setattr("app.core.mailer.resend.Emails.send", lambda params: sent.append(params))
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://test"
    ) as client:
        data = {"email": "independent-modes@example.com", "password": secrets.token_urlsafe(32)}
        response = await client.post("/api/v1/auth/preregister", json=data)
        assert response.status_code == 204, response.text
        assert len(sent) == 1 and sent[0]["to"] == [data["email"]]
        code = re.search(r"\b\d{6}\b", sent[0]["text"])[0]
        confirmed = await client.post("/api/v1/auth/confirm", json={
            "email": data["email"], "otp_code": code,
        })
        assert confirmed.status_code == 204, confirmed.text
        login = await client.post("/api/v1/auth/jwt/login", data={
            "username": data["email"], "password": data["password"],
        })
        assert login.status_code == 200, login.text
