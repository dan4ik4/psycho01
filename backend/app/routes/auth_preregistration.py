import asyncio

from fastapi import APIRouter, Depends, Request, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.deps import get_db
from app.schemas.pending_registration import (
    PendingRegistrationCreate,
    PendingRegistrationConfirm,
    PendingRegistrationResend,
)
from app.services.registration import (
    pre_register_user,
    confirm_registration,
    resend_registration_code,
)

from app.core.rate_limiter import limiter
from app.core.settings import settings
from fastapi_users.password import PasswordHelper


router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/preregister", status_code=status.HTTP_204_NO_CONTENT)
@limiter.limit(settings.AUTH_PREREGISTER_RATE_LIMIT)
async def preregister(
    request: Request,
    data: PendingRegistrationCreate,
    db: AsyncSession = Depends(get_db),
) -> None:
    
    password_helper = PasswordHelper()
    password_hash = await asyncio.to_thread(
        password_helper.hash,
        data.password,
    )

    await pre_register_user(
        db,
        email=data.email,
        password_hash=password_hash,
    )


@router.post("/confirm", status_code=status.HTTP_204_NO_CONTENT)
@limiter.limit(settings.AUTH_CONFIRM_RATE_LIMIT)
async def confirm_registration_code(
    request: Request,
    data: PendingRegistrationConfirm,
    db: AsyncSession = Depends(get_db),
) -> None:
    await confirm_registration(
        db,
        email=data.email,
        otp_code=data.otp_code,
    )


@router.post("/resend", status_code=status.HTTP_204_NO_CONTENT)
@limiter.limit(settings.AUTH_RESEND_RATE_LIMIT)
async def resend_registration_code_route(
    request: Request,
    data: PendingRegistrationResend,
    db: AsyncSession = Depends(get_db),
) -> None:
    await resend_registration_code(
        db,
        email=data.email,
    )