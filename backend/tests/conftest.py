"""Integration tests use a dedicated loopback PostgreSQL database, never the app DB."""

import os
import re
import subprocess
import sys
from datetime import timedelta
from pathlib import Path

import pytest_asyncio
from sqlalchemy import text

if os.environ.get("TEST_MODE", "").lower() != "true" or os.environ.get(
    "DB_HOST"
) not in ("127.0.0.1", "localhost"):
    raise RuntimeError(
        "Run tests with python scripts/run_tests.py (disposable database)"
    )
test_name = os.environ.get("PSYCHO_TEST_DATABASE", "")
if not re.fullmatch(r"psycho01_test_[0-9a-f]{12}", test_name) or os.environ.get(
    "DB_NAME"
) != test_name:
    raise RuntimeError("Tests require a disposable database created by run_tests.py")
os.environ["SCHEDULER_ENABLED"] = "false"
subprocess.run(
    [sys.executable, "-m", "alembic", "upgrade", "head"],
    check=True,
    cwd=Path(__file__).resolve().parents[1],
)

from app.billing.models import PsychologistBilling, now
from app.db.base import Base
from app.db.session import AsyncSessionLocal, engine
from app.models.patient_assignment import PatientAssignment
from app.models.patient_assignment_event import (
    PatientAssignmentEvent,
    PatientAssignmentEventType,
)
from app.models.slot import Slot
from app.models.slot_event import SlotEvent, SlotEventType
from app.models.user import User


@pytest_asyncio.fixture(autouse=True)
async def clean_database():
    assert engine.url.database == test_name
    async with engine.begin() as conn:
        names = ", ".join('"' + name + '"' for name in Base.metadata.tables)
        await conn.execute(
            text("TRUNCATE TABLE " + names + " RESTART IDENTITY CASCADE")
        )
    yield
    await engine.dispose()


@pytest_asyncio.fixture
async def domain():
    async with AsyncSessionLocal() as db:
        patient = User(
            email="patient@example.com",
            hashed_password="!disabled-patient-login",
            is_active=True,
            is_verified=True,
            is_superuser=False,
            is_psychologist=False,
        )
        psychologist = User(
            email="psy@example.com",
            hashed_password="!disabled-psychologist-login",
            is_active=True,
            is_verified=True,
            is_superuser=False,
            is_psychologist=True,
        )
        stranger = User(
            email="other@example.com",
            hashed_password="!disabled-stranger-login",
            is_active=True,
            is_verified=True,
            is_superuser=False,
            is_psychologist=False,
        )
        db.add_all([patient, psychologist, stranger])
        await db.flush()
        assignment = PatientAssignment(
            patient_id=patient.id, psychologist_id=psychologist.id
        )
        slot = Slot(
            psychologist_id=psychologist.id,
            start_at=now() + timedelta(hours=2),
            end_at=now() + timedelta(hours=3),
        )
        db.add_all([assignment, slot])
        await db.flush()
        db.add_all(
            [
                PatientAssignmentEvent(
                    assignment_id=assignment.id,
                    event_type=PatientAssignmentEventType.ACCEPTED,
                    performed_by_id=psychologist.id,
                ),
                SlotEvent(
                    slot_id=slot.id,
                    event_type=SlotEventType.CREATED,
                    performed_by_id=psychologist.id,
                ),
                PsychologistBilling(
                    user_id=psychologist.id, hourly_net_minor=300000, currency="RUB"
                ),
            ]
        )
        await db.commit()
        return patient, psychologist, stranger, assignment, slot
