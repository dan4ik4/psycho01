import uuid
from datetime import date, datetime, timezone

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    UniqueConstraint,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


def now():
    return datetime.now(timezone.utc)


class Subscription(Base):
    __tablename__ = "billing_subscriptions"
    __table_args__ = (UniqueConstraint("user_id", "test_mode"),)
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT"), index=True
    )
    test_mode: Mapped[bool] = mapped_column(Boolean, nullable=False)
    provider: Mapped[str] = mapped_column(String(30))
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    will_renew: Mapped[bool] = mapped_column(Boolean, default=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)


class SubscriptionPurchase(Base):
    __tablename__ = "billing_subscription_purchases"
    __table_args__ = (UniqueConstraint("user_id", "request_id"),)
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT")
    )
    request_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True))
    amount_minor: Mapped[int] = mapped_column(BigInteger)
    currency: Mapped[str] = mapped_column(String(3))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)


class AiUsage(Base):
    __tablename__ = "billing_ai_usage"
    __table_args__ = (CheckConstraint("used >= 0", name="ck_ai_usage_nonnegative"),)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    day: Mapped[date] = mapped_column(Date, primary_key=True)
    test_mode: Mapped[bool] = mapped_column(Boolean, primary_key=True)
    used: Mapped[int] = mapped_column(Integer, default=0)


class PsychologistBilling(Base):
    __tablename__ = "billing_psychologists"
    __table_args__ = (
        CheckConstraint("hourly_net_minor > 0", name="ck_hourly_net_positive"),
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT"), primary_key=True
    )
    hourly_net_minor: Mapped[int] = mapped_column(BigInteger)
    currency: Mapped[str] = mapped_column(String(3))
    stripe_account_id: Mapped[str | None] = mapped_column(String(100), unique=True)
    charges_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    payouts_enabled: Mapped[bool] = mapped_column(Boolean, default=False)


class PricingPolicy(Base):
    __tablename__ = "billing_pricing_policies"
    __table_args__ = (
        CheckConstraint(
            "tax_bps >= 0 AND platform_bps >= 0 AND processor_bps >= 0 AND tax_bps + platform_bps + processor_bps < 10000 AND processor_fixed_minor >= 0",
            name="ck_pricing_policy",
        ),
    )
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    test_mode: Mapped[bool] = mapped_column(Boolean)
    tax_bps: Mapped[int] = mapped_column(Integer)
    platform_bps: Mapped[int] = mapped_column(Integer)
    processor_bps: Mapped[int] = mapped_column(Integer)
    processor_fixed_minor: Mapped[int] = mapped_column(BigInteger)
    created_by_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL")
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=now, index=True
    )


class Booking(Base):
    __tablename__ = "billing_bookings"
    __table_args__ = (
        UniqueConstraint("patient_id", "request_id"),
        CheckConstraint(
            "status IN ('pending','confirmed','cancelled','expired','completed','missed')",
            name="ck_booking_status",
        ),
        Index(
            "uq_booking_active_slot",
            "slot_id",
            unique=True,
            postgresql_where=text("status IN ('pending','confirmed')"),
        ),
    )
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    slot_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("slots.id", ondelete="RESTRICT"), index=True
    )
    assignment_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("patient_assignments.id", ondelete="RESTRICT")
    )
    patient_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT"), index=True
    )
    psychologist_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT"), index=True
    )
    request_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True))
    booked_event_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("slot_events.id", ondelete="RESTRICT"), unique=True
    )
    test_mode: Mapped[bool] = mapped_column(Boolean)
    legacy: Mapped[bool] = mapped_column(Boolean, default=False)
    status: Mapped[str] = mapped_column(String(20), default="pending")
    quote: Mapped[dict] = mapped_column(JSONB, default=dict)
    hold_until: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
    outcome: Mapped[str | None] = mapped_column(String(40))
    finalized_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Payment(Base):
    __tablename__ = "billing_payments"
    __table_args__ = (CheckConstraint("amount_minor > 0", name="ck_payment_positive"),)
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    booking_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("billing_bookings.id", ondelete="RESTRICT"), unique=True
    )
    provider: Mapped[str] = mapped_column(String(30))
    status: Mapped[str] = mapped_column(String(30), default="pending")
    amount_minor: Mapped[int] = mapped_column(BigInteger)
    currency: Mapped[str] = mapped_column(String(3))
    external_id: Mapped[str | None] = mapped_column(String(200), unique=True)
    checkout_id: Mapped[str | None] = mapped_column(String(200), unique=True)
    checkout_url: Mapped[str | None] = mapped_column(String(2000))
    checkout_started_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True)
    )
    destination: Mapped[str | None] = mapped_column(String(100))
    actual_fee_minor: Mapped[int | None] = mapped_column(BigInteger)
    actual_fee_currency: Mapped[str | None] = mapped_column(String(3))
    source_charge: Mapped[str | None] = mapped_column(String(200))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)


class MoneyOperation(Base):
    """Durable outbox for full refunds and psychologist transfers."""

    __tablename__ = "billing_operations"
    __table_args__ = (
        UniqueConstraint("payment_id", "kind"),
        CheckConstraint(
            "kind IN ('refund','transfer') AND amount_minor > 0",
            name="ck_money_operation",
        ),
    )
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    payment_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("billing_payments.id", ondelete="RESTRICT")
    )
    kind: Mapped[str] = mapped_column(String(20))
    amount_minor: Mapped[int] = mapped_column(BigInteger)
    status: Mapped[str] = mapped_column(String(20), default="pending")
    external_id: Mapped[str | None] = mapped_column(String(200), unique=True)
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    retry_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=now, index=True
    )
    lease_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_error: Mapped[str | None] = mapped_column(String(500))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)


class Earning(Base):
    __tablename__ = "billing_earnings"
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    booking_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("billing_bookings.id", ondelete="RESTRICT"), unique=True
    )
    psychologist_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT"), index=True
    )
    test_mode: Mapped[bool] = mapped_column(Boolean)
    net_minor: Mapped[int] = mapped_column(BigInteger)
    currency: Mapped[str] = mapped_column(String(3))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=now, index=True
    )


class ProviderEvent(Base):
    __tablename__ = "billing_provider_events"
    __table_args__ = (UniqueConstraint("provider", "external_id"),)
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    provider: Mapped[str] = mapped_column(String(30))
    external_id: Mapped[str] = mapped_column(String(200))
    payload: Mapped[dict] = mapped_column(JSONB)
    status: Mapped[str] = mapped_column(String(20), default="pending")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
    last_error: Mapped[str | None] = mapped_column(String(500))
