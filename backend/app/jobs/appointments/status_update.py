import logging
from datetime import datetime, timedelta, UTC

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.appointment import Appointment, AppointmentStatus, MissedBy
from app.db.session import AsyncSessionLocal

logger = logging.getLogger(__name__)


async def update_appointment_statuses(session: AsyncSession) -> int:
    now = datetime.now(UTC)

    stmt = (
        select(Appointment)
        .options(selectinload(Appointment.slot))
        .where(
            Appointment.status.in_(
                [AppointmentStatus.scheduled, AppointmentStatus.in_progress]
            )
        )
    )

    result = await session.execute(stmt)
    appointments = result.scalars().all()

    updated = 0

    for appt in appointments:
        start = appt.slot.start_at - timedelta(minutes=5)
        end = appt.slot.end_at + timedelta(minutes=5)

        # scheduled -> in_progress
        if (
            appt.status == AppointmentStatus.scheduled
            and start <= now < end
        ):
            appt.status = AppointmentStatus.in_progress
            updated += 1

        elif now >= end:
            patient_joined = appt.patient_joined_at is not None
            psychologist_joined = appt.psychologist_joined_at is not None

            if patient_joined and psychologist_joined:
                appt.status = AppointmentStatus.completed
                appt.missed_by = None
            elif psychologist_joined and not patient_joined:
                appt.status = AppointmentStatus.missed
                appt.missed_by = MissedBy.patient
            elif patient_joined and not psychologist_joined:
                appt.status = AppointmentStatus.missed
                appt.missed_by = MissedBy.psychologist
            else:
                appt.status = AppointmentStatus.missed
                appt.missed_by = MissedBy.both

            updated += 1

    await session.commit()

    logger.info("Updated %s appointment statuses", updated)
    return updated


async def run_appointment_status_update() -> None:
    try:
        async with AsyncSessionLocal() as session:
            count = await update_appointment_statuses(session)
            logger.info("Appointment status job finished. Updated: %s", count)
    except Exception:
        logger.exception("Appointment status job failed")