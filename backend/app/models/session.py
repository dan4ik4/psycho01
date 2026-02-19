import uuid
from datetime import datetime
from sqlalchemy import ForeignKey, String, Enum as SAEnum, TIMESTAMP, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db.base import Base
import enum

class SessionStatus(str, enum.Enum):
    requested = "requested"
    approved = "approved"
    rejected = "rejected"
    canceled = "canceled"
    finished = "finished"


class Session(Base):
    __tablename__ = "sessions"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False
    )

    psychologist_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False
    )

    scheduled_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), nullable=False)

    status: Mapped[SessionStatus] = mapped_column(
        SAEnum(SessionStatus, name="sessionstatus"),
        nullable=False,
        default=SessionStatus.requested
    )

    jitsi_url: Mapped[str | None] = mapped_column(String(512), nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True),
        server_default=func.now(),
        nullable=False
    )

    # relationships (не обязательны, но могут пригодиться)
    user = relationship("User", foreign_keys=[user_id])
    psychologist = relationship("User", foreign_keys=[psychologist_id])