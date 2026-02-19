from sqlalchemy import Column, ForeignKey, Integer, String, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from app.db.base import Base


class PsychologistProfile(Base):
    __tablename__ = "psychologist_profile"

    id = Column(Integer, primary_key=True)
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        unique=True,
        nullable=False,
        index=True,
    )

    user = relationship("User", back_populates="psychologist_profile", passive_deletes=True)

    specialization = Column(String(255))
    experience_years = Column(Integer)
    license_number = Column(String(255))
    price_per_hour = Column(Integer)
    bio = Column(Text)