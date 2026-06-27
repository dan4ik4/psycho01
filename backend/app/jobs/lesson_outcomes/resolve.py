from app.db.session import AsyncSessionLocal
from app.services.lesson_finalization_service import resolve_expired_lesson_outcomes


async def resolve_expired_lesson_outcomes_job() -> None:
    async with AsyncSessionLocal() as db:
        await resolve_expired_lesson_outcomes(db)