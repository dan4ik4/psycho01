from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import delete, func, select
from datetime import datetime

from app.models.pending_registration import PendingRegistration
from app.core.email import normalize_email


async def get_pending_by_email(
    db: AsyncSession,
    email: str,
    *,
    for_update: bool = False,
) -> PendingRegistration | None:
    normalized_email = normalize_email(email)

    query = select(PendingRegistration).where(
        func.lower(PendingRegistration.email) == normalized_email
    )

    if for_update:
        query = query.with_for_update()

    result = await db.execute(query)

    return result.scalar_one_or_none()

async def create_pending_registration(
    db: AsyncSession,
    *,
    email: str,
    hashed_password: str,
    otp_code_hash: str,
    last_sent_at: datetime,
) -> PendingRegistration:
    pending = PendingRegistration(
        email=normalize_email(email),
        hashed_password=hashed_password,
        otp_code_hash=otp_code_hash,
        otp_attempts=0,
        last_sent_at=last_sent_at,
        resend_count=0,
    )

    db.add(pending)
    await db.flush()
    await db.refresh(pending)

    return pending

async def update_pending_registration_code(
    db: AsyncSession,
    pending: PendingRegistration,
    *,
    otp_code_hash: str,
    last_sent_at: datetime,
) -> PendingRegistration:
    pending.otp_code_hash = otp_code_hash
    pending.otp_attempts = 0
    pending.last_sent_at = last_sent_at
    pending.resend_count += 1

    await db.flush()
    await db.refresh(pending)

    return pending

async def increment_otp_attempts(
    db: AsyncSession,
    pending: PendingRegistration,
) -> PendingRegistration:
    pending.otp_attempts += 1

    await db.flush()
    await db.refresh(pending)

    return pending

async def delete_pending_registration(
    db: AsyncSession,
    pending: PendingRegistration,
) -> None:
    await db.delete(pending)
    await db.flush()

async def delete_expired_pending_registrations(
    db: AsyncSession,
    *,
    older_than: datetime,
) -> int:
    result = await db.execute(
        delete(PendingRegistration).where(
            PendingRegistration.last_sent_at < older_than
        )
    )

    await db.flush()

    return result.rowcount or 0