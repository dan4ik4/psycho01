import asyncio

import resend

from app.core.settings import settings


async def send_email(to: str, subject: str, text: str) -> None:
    if settings.TEST_MODE:
        # Local tests must not send real email. Use seeded accounts for the demo.
        return
    resend.api_key = settings.RESEND_API_KEY

    params: resend.Emails.SendParams = {
        "from": settings.RESEND_FROM_EMAIL,
        "to": [to],
        "subject": subject,
        "text": text,
    }

    await asyncio.to_thread(resend.Emails.send, params)
