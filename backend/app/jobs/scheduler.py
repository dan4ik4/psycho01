from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.interval import IntervalTrigger

from app.jobs.pending_registrations.cleanup import run_cleanup_pending_registrations

scheduler = AsyncIOScheduler()


def start_scheduler():

    scheduler.add_job(
        run_cleanup_pending_registrations,
        IntervalTrigger(hours=1),
        id="pending_registrations_cleanup",
        replace_existing=True,
    )

    scheduler.start()


def stop_scheduler():
    scheduler.shutdown()