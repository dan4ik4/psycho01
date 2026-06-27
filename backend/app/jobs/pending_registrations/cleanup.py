from datetime import datetime, timezone, timedelta
import logging

from app.core.settings import settings
from app.db.session import AsyncSessionLocal
from app.crud.pending_registration import delete_expired_pending_registrations

logger = logging.getLogger(__name__)


async def run_cleanup_pending_registrations() -> None:
    async with AsyncSessionLocal() as db:
        older_than = datetime.now(timezone.utc) - timedelta(
            hours=settings.REG_PENDING_CLEANUP_HOURS
        )

        deleted = await delete_expired_pending_registrations(
            db,
            older_than=older_than,
        )

        await db.commit()

        logger.info(f"Pending registrations cleanup: deleted={deleted}")