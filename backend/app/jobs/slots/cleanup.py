import logging
from datetime import datetime, UTC

from sqlalchemy import delete, exists, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.appointment import Appointment, AppointmentStatus, AvailabilitySlot
from app.db.session import AsyncSessionLocal

logger = logging.getLogger(__name__)


async def delete_expired_unbooked_slots(session: AsyncSession) -> int:
    now = datetime.now(UTC)

    booked_or_active_appointment_exists = exists(
        select(Appointment.id).where(
            Appointment.slot_id == AvailabilitySlot.id,
            Appointment.status != AppointmentStatus.cancelled,
        )
    )

    stmt = (
        delete(AvailabilitySlot)
        .where(
            AvailabilitySlot.end_at < now,
            ~booked_or_active_appointment_exists,
        )
        .returning(AvailabilitySlot.id)
    )

    result = await session.execute(stmt)
    deleted_ids = result.scalars().all()
    await session.commit()

    deleted_count = len(deleted_ids)
    logger.info("Deleted %s expired unbooked slots", deleted_count)

    return deleted_count

async def run_expired_slots_cleanup() -> None:
    try:
        async with AsyncSessionLocal() as session:
            deleted_count = await delete_expired_unbooked_slots(session)
            logger.info("Expired slots cleanup finished. Deleted: %s", deleted_count)
    except Exception:
        logger.exception("Expired slots cleanup job failed")