"""Exercise billing upgrade against an existing unpaid booking in the disposable test DB."""

import os
import subprocess
import sys
from pathlib import Path

from app.billing.models import Booking, Payment
from app.billing.service import assert_call_paid
from app.crud.slot import create_slot_event
from app.db.session import AsyncSessionLocal, engine
from app.models.slot_event import SlotEventType
from sqlalchemy import func, select


async def test_upgrade_preserves_legacy_booking_without_retroactive_payment(domain):
    assert engine.url.database == os.environ["DB_NAME"] == os.environ["PSYCHO_TEST_DATABASE"]
    async with AsyncSessionLocal() as db:
        event = await create_slot_event(
            db, domain[4].id, SlotEventType.BOOKED, patient_id=domain[0].id
        )
        await db.commit()
    await engine.dispose()
    root = Path(__file__).resolve().parents[1]
    try:
        subprocess.run(
            [sys.executable, "-m", "alembic", "downgrade", "44752d9c4ff7"],
            cwd=root,
            check=True,
            capture_output=True,
        )
    finally:
        subprocess.run(
            [sys.executable, "-m", "alembic", "upgrade", "head"],
            cwd=root,
            check=True,
            capture_output=True,
        )
    async with AsyncSessionLocal() as db:
        booking = await db.scalar(
            select(Booking).where(Booking.slot_id == domain[4].id)
        )
        assert booking and booking.legacy and booking.status == "confirmed"
        assert booking.booked_event_id == event.id and booking.quote == {}
        assert await db.scalar(select(func.count()).select_from(Payment)) == 0
        await assert_call_paid(db, event)
