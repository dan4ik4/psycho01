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
    assert (
        engine.url.database
        == os.environ["DB_NAME"]
        == os.environ["PSYCHO_TEST_DATABASE"]
    )
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


async def test_usd_migration_resets_rates_but_preserves_money_history(domain):
    import uuid

    from app.billing.models import PricingPolicy, PsychologistBilling
    from app.billing.pricing import pricing_rates
    from app.billing.service import reserve_booking

    async with AsyncSessionLocal() as db:
        profile = await db.get(PsychologistBilling, domain[1].id)
        profile.currency = "RUB"
        db.add(
            PricingPolicy(
                test_mode=True,
                currency="RUB",
                tax_bps=0,
                platform_bps=1000,
                processor_bps=0,
                processor_fixed_minor=3000,
            )
        )
        await db.commit()
        booking = await reserve_booking(db, domain[4].id, domain[0], uuid.uuid4())
        original_quote = dict(booking.quote)
        payment = await db.scalar(
            select(Payment).where(Payment.booking_id == booking.id)
        )
        original_payment = (payment.amount_minor, payment.currency)
        booking_id, payment_id = booking.id, payment.id
    await engine.dispose()
    root = Path(__file__).resolve().parents[1]
    try:
        subprocess.run(
            [sys.executable, "-m", "alembic", "downgrade", "b07625e126ed"],
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
        profile = await db.get(PsychologistBilling, domain[1].id)
        assert profile.currency == "USD" and profile.hourly_net_minor is None
        assert (await db.get(Booking, booking_id)).quote == original_quote
        payment = await db.get(Payment, payment_id)
        assert (payment.amount_minor, payment.currency) == original_payment
        assert payment.currency == "RUB"
        assert (await pricing_rates(db, "USD"))[0] == (0, 0, 0, 0)
        assert (await pricing_rates(db, "RUB"))[0] == (0, 1000, 0, 3000)
