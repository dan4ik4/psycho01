from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi_users.password import PasswordHelper
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.mailer import send_email
from app.core.otp import generate_code6, hash_code
from app.core.settings import settings
from app.db.deps import get_db
from app.models.pending_registration import PendingRegistration
from app.models.user import User, UserRole
from app.schemas.auth_preregistration import ConfirmIn, PreRegisterIn

router = APIRouter(prefix="/auth", tags=["auth"])

password_helper = PasswordHelper()


@router.post("/pre-register", status_code=200)
async def pre_register(payload: PreRegisterIn, db: AsyncSession = Depends(get_db)):
    # 1) если юзер уже есть — стоп
    exists = await db.execute(select(User.id).where(User.email == payload.email))
    if exists.scalar_one_or_none():
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Email already registered")

    # 2) генерим код
    code = generate_code6()
    code_h = hash_code(code, settings.REG_CODE_SECRET)

    expires_at = datetime.now(timezone.utc) + timedelta(minutes=int(settings.REG_CODE_TTL_MINUTES))

    # 3) хэш пароля (чтобы не хранить plaintext)
    pwd_hash = password_helper.hash(payload.password)

    # 4) перезаписываем pending (один email = одна заявка)
    res_pending = await db.execute(
        select(PendingRegistration).where(PendingRegistration.email == payload.email)
    )
    pending = res_pending.scalar_one_or_none()

    now = datetime.now(timezone.utc)

    if pending:
        cooldown = int(settings.REG_CODE_RESEND_COOLDOWN_SECONDS)
        if (now - pending.last_sent_at).total_seconds() < cooldown:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail=f"Please wait {cooldown} seconds before requesting a new code",
            )

        pending.password_hash = pwd_hash
        pending.code_hash = code_h
        pending.attempts = 0
        pending.expires_at = expires_at
        pending.last_sent_at = now
    else:
        db.add(
            PendingRegistration(
                email=payload.email,
                password_hash=pwd_hash,
                code_hash=code_h,
                attempts=0,
                expires_at=expires_at,
                last_sent_at=now,
            )
        )

    await db.commit()

    # 5) отправляем код
    await send_email(
        to=payload.email,
        subject="Код подтверждения",
        text=f"Ваш код подтверждения: {code}\n\nКод действует {settings.REG_CODE_TTL_MINUTES} минут.",
    )

    return {"ok": True}


@router.post("/confirm", status_code=200)
async def confirm(payload: ConfirmIn, db: AsyncSession = Depends(get_db)):
    res = await db.execute(
    select(PendingRegistration)
    .where(PendingRegistration.email == payload.email)
    .with_for_update()
    )
    pending = res.scalar_one_or_none()
    if not pending:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No pending registration")

    now = datetime.now(timezone.utc)
    if pending.expires_at <= now:
        await db.delete(pending)
        await db.commit()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Code expired")

    if pending.attempts >= int(settings.REG_CODE_MAX_ATTEMPTS):
        await db.delete(pending)
        await db.commit()
        raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail="Too many attempts")

    code_h = hash_code(payload.code, settings.REG_CODE_SECRET)
    if code_h != pending.code_hash:
        pending.attempts += 1
        await db.commit()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid code")

    # финально: создаём юзера ТОЛЬКО сейчас
    user = User(
        email=pending.email,
        hashed_password=pending.password_hash,
        is_active=True,
        is_superuser=False,
        is_verified=True,  # можешь поставить True, если считаешь код=верификация
        role=UserRole.user,
    )
    db.add(user)
    await db.delete(pending)

    try:
        await db.commit()
    except Exception:
        await db.rollback()
        raise

    return {"ok": True}
