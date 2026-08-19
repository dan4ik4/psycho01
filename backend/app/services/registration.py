from datetime import datetime, timedelta, timezone

from fastapi import HTTPException, status
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.email import normalize_email
from app.core.errors import ConflictError
from app.core.mailer import send_email
from app.core.otp import generate_code6, hash_code, verify_code
from app.core.settings import settings
from app.crud.pending_registration import (
    create_pending_registration,
    delete_pending_registration,
    get_pending_by_email,
    increment_otp_attempts,
    update_pending_registration_code,
)
from app.crud.user import create_user, get_user_by_email


async def _lock_registration_email(
    db: AsyncSession,
    email: str,
) -> None:
    await db.execute(
        text(
            """
            SELECT pg_advisory_xact_lock(
                hashtextextended(:email, 0)
            )
            """
        ),
        {
            "email": normalize_email(email),
        },
    )


async def pre_register_user(
    db: AsyncSession,
    *,
    email: str,
    password_hash: str,
) -> None:
    email = normalize_email(email)

    await _lock_registration_email(
        db,
        email,
    )

    existing_user = await get_user_by_email(
        db,
        email,
    )

    if existing_user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="User with this email already exists",
        )

    pending = await get_pending_by_email(
        db,
        email,
    )

    if pending is not None:
        raise ConflictError(
            "Registration is already pending"
        )

    now = datetime.now(timezone.utc)

    code = generate_code6()
    code_hash = hash_code(
        code,
        settings.REG_CODE_SECRET,
    )

    try:
        await create_pending_registration(
            db,
            email=email,
            hashed_password=password_hash,
            otp_code_hash=code_hash,
            last_sent_at=now,
        )
    except IntegrityError as error:
        await db.rollback()

        raise ConflictError(
            "Registration is already pending"
        ) from error

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
    email = normalize_email(email)

    await _lock_registration_email(
        db,
        email,
    )

    pending = await get_pending_by_email(
        db,
        email,
        for_update=True,
    )

    if not pending:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Registration request not found",
        )

    now = datetime.now(timezone.utc)

    expires_at = pending.last_sent_at + timedelta(
        minutes=settings.REG_CODE_TTL_MINUTES
    )

    if now > expires_at:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Code expired. Please request a new code.",
        )

    if pending.otp_attempts >= settings.REG_CODE_MAX_ATTEMPTS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Too many attempts",
        )

    if not verify_code(
        otp_code,
        pending.otp_code_hash,
        settings.REG_CODE_SECRET,
    ):
        await increment_otp_attempts(
            db,
            pending,
        )
        await db.commit()

        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid code",
        )

    await create_user(
        db,
        email=pending.email,
        hashed_password=pending.hashed_password,
    )

    await delete_pending_registration(
        db,
        pending,
    )

    await db.commit()


async def resend_registration_code(
    db: AsyncSession,
    *,
    email: str,
) -> None:
    email = normalize_email(email)

    await _lock_registration_email(
        db,
        email,
    )

    pending = await get_pending_by_email(
        db,
        email,
        for_update=True,
    )

    if not pending:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Registration request not found",
        )

    now = datetime.now(timezone.utc)

    seconds_since_last_send = (
        now - pending.last_sent_at
    ).total_seconds()

    if (
        seconds_since_last_send
        < settings.REG_CODE_RESEND_COOLDOWN_SECONDS
    ):
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
    code_hash = hash_code(
        code,
        settings.REG_CODE_SECRET,
    )

    await update_pending_registration_code(
        db,
        pending,
        otp_code_hash=code_hash,
        last_sent_at=now,
    )

    await send_email(
        to=email,
        subject="Registration code",
        text=f"Your registration code: {code}",
    )

    await db.commit()