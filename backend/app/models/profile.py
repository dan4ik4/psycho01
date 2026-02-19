import uuid

from sqlalchemy import Column, Date, ForeignKey, Integer, String, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from app.db.base import Base


class Profile(Base):
    __tablename__ = "profiles"

    id = Column(Integer, primary_key=True)
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        unique=True,
        nullable=False,
        index=True,
    )

    display_name = Column(String(120))
    bio = Column(Text)
    timezone = Column(String(64))
    avatar_url = Column(String(512))
    phone = Column(String(32))
    telegram = Column(String(64))
    birth_date = Column(Date)

    user = relationship("User", back_populates="profile", passive_deletes=True)