from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.interval import IntervalTrigger

from app.jobs.slots.cleanup import run_expired_slots_cleanup
from app.jobs.appointments.status_update import run_appointment_status_update

scheduler = AsyncIOScheduler()


def start_scheduler():
    scheduler.add_job(
        run_expired_slots_cleanup,
        IntervalTrigger(minutes=1),
        id="slots_cleanup",
        replace_existing=True,
    )

    scheduler.add_job(
        run_appointment_status_update,
        IntervalTrigger(minutes=1),
        id="appointment_status_update",
        replace_existing=True,
    )

    scheduler.start()


def stop_scheduler():
    scheduler.shutdown()