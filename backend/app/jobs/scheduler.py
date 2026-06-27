from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.interval import IntervalTrigger

from app.jobs.lesson_outcomes.resolve import resolve_expired_lesson_outcomes_job
from app.jobs.pending_registrations.cleanup import run_cleanup_pending_registrations

scheduler = AsyncIOScheduler()


def start_scheduler():
    
    scheduler.add_job(
        resolve_expired_lesson_outcomes_job,
        "interval",
        minutes=5,
        id="resolve_expired_lesson_outcomes",
        replace_existing=True,
    )

    scheduler.add_job(
        run_cleanup_pending_registrations,
        "interval",
        minutes=5,
        id="resolve_expired_lesson_outcomes",
        replace_existing=True,
    )

    scheduler.start()


def stop_scheduler():
    scheduler.shutdown()