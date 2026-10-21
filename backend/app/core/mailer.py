import asyncio
import logging

import resend

from app.core.settings import settings


async def send_email(to: str, subject: str, text: str) -> None:
    if settings.EMAIL_TEST_MODE:
        # Suppress delivery only when email testing is enabled.
        return
    resend.api_key = settings.RESEND_API_KEY

    params: resend.Emails.SendParams = {
        "from": settings.RESEND_FROM_EMAIL,
        "to": [to],
        "subject": subject,
        "text": text,
    }

    result = await asyncio.to_thread(resend.Emails.send, params)
    if isinstance(result, dict) and result.get("id"):
        logging.getLogger("uvicorn.error").info(
            "Email accepted by Resend: message_id=%s", result["id"]
        )
