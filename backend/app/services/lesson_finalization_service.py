from datetime import datetime, timedelta, timezone

from sqlalchemy import and_, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.call import Call
from app.models.call_event import CallEvent, CallEventType
from app.models.slot import Slot
from app.models.slot_event import SlotEvent, SlotEventType
from app.core.settings import settings


async def resolve_expired_lesson_outcomes(
    db: AsyncSession,
    limit: int = 100,
) -> int:
    now = datetime.now(timezone.utc)

    finalization_cutoff = now - timedelta(
        minutes=settings.AGORA_JOIN_WINDOW_MINUTES,
    )

    ranked_events_subquery = (
        select(
            SlotEvent.id.label("event_id"),
            SlotEvent.slot_id.label("slot_id"),
            func.row_number()
            .over(
                partition_by=SlotEvent.slot_id,
                order_by=(
                    SlotEvent.created_at.desc(),
                    SlotEvent.id.desc(),
                ),
            )
            .label("event_position"),
        )
        .subquery()
    )

    stmt = (
        select(
            Slot,
            SlotEvent,
        )
        .join(
            ranked_events_subquery,
            and_(
                ranked_events_subquery.c.slot_id == Slot.id,
                ranked_events_subquery.c.event_position == 1,
            ),
        )
        .join(
            SlotEvent,
            SlotEvent.id == ranked_events_subquery.c.event_id,
        )
        .where(
            Slot.end_at <= finalization_cutoff,
            SlotEvent.event_type == SlotEventType.BOOKED,
        )
        .order_by(
            Slot.end_at.asc(),
            Slot.id.asc(),
        )
        .limit(limit)
        .with_for_update(
            of=Slot,
            skip_locked=True,
        )
    )

    result = await db.execute(stmt)
    rows = list(result.all())

    if not rows:
        return 0

    slot_ids = [
        slot.id
        for slot, _ in rows
    ]

    booked_at_by_slot = {
        slot.id: latest_event.created_at
        for slot, latest_event in rows
    }

    join_until_by_slot = {
        slot.id: slot.end_at
        + timedelta(
            minutes=settings.AGORA_JOIN_WINDOW_MINUTES,
        )
        for slot, _ in rows
    }

    joined_result = await db.execute(
        select(
            Call.slot_id,
            CallEvent.user_id,
            CallEvent.created_at,
        )
        .join(
            CallEvent,
            CallEvent.call_id == Call.id,
        )
        .where(
            Call.slot_id.in_(slot_ids),
            CallEvent.event_type == CallEventType.JOINED,
        )
    )

    joined_users_by_slot: dict = {}

    for slot_id, user_id, joined_at in joined_result.all():
        if user_id is None:
            continue

        booked_at = booked_at_by_slot.get(slot_id)
        join_until = join_until_by_slot.get(slot_id)

        if booked_at is None or join_until is None:
            continue

        if joined_at < booked_at:
            continue

        if joined_at > join_until:
            continue

        joined_users_by_slot.setdefault(
            slot_id,
            set(),
        ).add(user_id)

    final_events: list[SlotEvent] = []

    for slot, latest_event in rows:
        patient_id = latest_event.patient_id

        if patient_id is None:
            continue

        joined_users = joined_users_by_slot.get(
            slot.id,
            set(),
        )

        patient_joined = (
            patient_id in joined_users
        )

        psychologist_joined = (
            slot.psychologist_id in joined_users
        )

        if patient_joined and psychologist_joined:
            event_type = SlotEventType.COMPLETED
            comment = (
                "Automatically marked as completed: "
                "both participants joined the call"
            )

        elif not patient_joined and psychologist_joined:
            event_type = SlotEventType.MISSED
            comment = (
                "Automatically marked as missed: "
                "patient did not join the call"
            )

        elif patient_joined and not psychologist_joined:
            event_type = SlotEventType.MISSED
            comment = (
                "Automatically marked as missed: "
                "psychologist did not join the call"
            )

        else:
            event_type = SlotEventType.MISSED
            comment = (
                "Automatically marked as missed: "
                "neither participant joined the call"
            )

        final_events.append(
            SlotEvent(
                slot_id=slot.id,
                patient_id=patient_id,
                event_type=event_type,
                performed_by_id=None,
                comment=comment,
            )
        )

    if not final_events:
        await db.rollback()
        return 0

    db.add_all(final_events)

    await db.commit()

    return len(final_events)