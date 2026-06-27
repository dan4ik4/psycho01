from datetime import datetime, timezone, timedelta

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.settings import settings
from app.core.otp import generate_code6, hash_code, verify_code
from app.crud.pending_registration import (
    get_pending_by_email,
    create_pending_registration,
    update_pending_registration_code,
    increment_otp_attempts,
    delete_pending_registration,
)
from app.crud.user import get_user_by_email, create_user
from app.core.mailer import send_email

async def pre_register_user(
    db: AsyncSession,
    *,
    email: str,
    password_hash: str,
) -> None:
    existing_user = await get_user_by_email(db, email)

    if existing_user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="User with this email already exists",
        )

    now = datetime.now(timezone.utc)
    pending = await get_pending_by_email(db, email)

    if pending:
        seconds_since_last_send = (now - pending.last_sent_at).total_seconds()

        if seconds_since_last_send < settings.REG_CODE_RESEND_COOLDOWN_SECONDS:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Please wait before requesting a new code",
            )

        if pending.resend_count >= settings.REG_CODE_MAX_RESENDS:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Registration code resend limit exceeded",
            )

    code = generate_code6()
    code_hash = hash_code(code, settings.REG_CODE_SECRET)

    if pending:
        await update_pending_registration_code(
            db,
            pending,
            hashed_password=password_hash,
            otp_code_hash=code_hash,
            last_sent_at=now,
        )
    else:
        await create_pending_registration(
            db,
            email=email,
            hashed_password=password_hash,
            otp_code_hash=code_hash,
            last_sent_at=now,
        )

    await send_email(
    to=email,
    subject="Registration code",
    text=f"Your registration code: {code}",
    )

    await db.commit()

async def confirm_registration(
    db: AsyncSession,
    *,
    email: str,
    otp_code: str,
) -> None:
    pending = await get_pending_by_email(db, email)

    if not pending:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Registration request not found",
        )

    now = datetime.now(timezone.utc)

    # проверка TTL
    expires_at = pending.last_sent_at + timedelta(
        minutes=settings.REG_CODE_TTL_MINUTES
    )

    if now > expires_at:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Code expired. Please request a new code.",
        )

    # проверка attempts
    if pending.otp_attempts >= settings.REG_CODE_MAX_ATTEMPTS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Too many attempts",
        )

    # проверка кода
    if not verify_code(otp_code, pending.otp_code_hash, settings.REG_CODE_SECRET):
        await increment_otp_attempts(db, pending)
        await db.commit()

        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid code",
        )

    # создаём пользователя
    await create_user(
        db,
        email=pending.email,
        hashed_password=pending.hashed_password,
    )

    # удаляем pending
    await delete_pending_registration(db, pending)

    await db.commit()

async def resend_registration_code(
    db: AsyncSession,
    *,
    email: str,
) -> None:
    pending = await get_pending_by_email(db, email)

    if not pending:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Registration request not found",
        )

    now = datetime.now(timezone.utc)

    seconds_since_last_send = (now - pending.last_sent_at).total_seconds()

    if seconds_since_last_send < settings.REG_CODE_RESEND_COOLDOWN_SECONDS:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Please wait before requesting a new code",
        )

    if pending.resend_count >= settings.REG_CODE_MAX_RESENDS:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Registration code resend limit exceeded",
        )

    code = generate_code6()
    code_hash = hash_code(code, settings.REG_CODE_SECRET)

    await update_pending_registration_code(
        db,
        pending,
        hashed_password=pending.hashed_password,
        otp_code_hash=code_hash,
        last_sent_at=now,
    )

    await send_email(
        to=email,
        subject="Registration code",
        text=f"Your registration code: {code}",
    )

    await db.commit()