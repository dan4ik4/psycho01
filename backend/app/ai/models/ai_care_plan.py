import uuid
import enum
from datetime import datetime
from sqlalchemy import Enum as SqlEnum
from sqlalchemy import (
    DateTime,
    ForeignKey,
    Integer,
    Text,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.sql import func

from app.db.base import Base

class AiCarePlanEventType(str, enum.Enum):
    ACTIVATED = "activated"
    PAUSED = "paused"
    COMPLETED = "completed"

class AiCarePlan(Base):
    __tablename__ = "ai_care_plans"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
    )

    assignment_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey(
            "patient_assignments.id",
            ondelete="CASCADE",
        ),
        unique=True,
        nullable=False,
        index=True,
    )

    created_by_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey(
            "users.id",
            ondelete="CASCADE",
        ),
        nullable=False,
        index=True,
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
        index=True,
    )

class AiCarePlanVersion(Base):
    __tablename__ = "ai_care_plan_versions"

    __table_args__ = (
        UniqueConstraint(
            "care_plan_id",
            "version",
            name="uq_ai_care_plan_versions_plan_version",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
    )

    care_plan_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey(
            "ai_care_plans.id",
            ondelete="CASCADE",
        ),
        nullable=False,
        index=True,
    )

    version: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
    )

    instructions_for_ai: Mapped[str] = mapped_column(
        Text,
        nullable=False,
    )

    patient_recommendations: Mapped[str | None] = mapped_column(
        Text,
        nullable=True,
    )

    created_by_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey(
            "users.id",
            ondelete="CASCADE",
        ),
        nullable=False,
        index=True,
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
        index=True,
    )

class AiCarePlanEvent(Base):
    __tablename__ = "ai_care_plan_events"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
    )

    care_plan_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey(
            "ai_care_plans.id",
            ondelete="CASCADE",
        ),
        nullable=False,
        index=True,
    )

    version_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey(
            "ai_care_plan_versions.id",
            ondelete="CASCADE",
        ),
        nullable=False,
        index=True,
    )

    event_type: Mapped[AiCarePlanEventType] = mapped_column(
        SqlEnum(
            AiCarePlanEventType,
            name="ai_care_plan_event_type",
        ),
        nullable=False,
        index=True,
    )

    actor_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey(
            "users.id",
            ondelete="CASCADE",
        ),
        nullable=False,
        index=True,
    )

    comment: Mapped[str | None] = mapped_column(
        Text,
        nullable=True,
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
        index=True,
    )

