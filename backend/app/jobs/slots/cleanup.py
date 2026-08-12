from app.db.session import AsyncSessionLocal
from app.services.slot import cleanup_expired_unbooked_slots


async def cleanup_expired_unbooked_slots_job() -> None:
    async with AsyncSessionLocal() as db:
        await cleanup_expired_unbooked_slots(
            db=db,
        )