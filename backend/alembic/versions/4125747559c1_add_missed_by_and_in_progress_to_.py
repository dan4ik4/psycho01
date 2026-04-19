"""add missed_by and in_progress to appointments

Revision ID: 4125747559c1
Revises: 4fef5c9b2284
Create Date: 2026-04-11 12:40:33.016615

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '4125747559c1'
down_revision: Union[str, Sequence[str], None] = '4fef5c9b2284'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    
    op.execute("ALTER TYPE appointment_status ADD VALUE IF NOT EXISTS 'in_progress'")

    
    missedby_enum = sa.Enum(
        "patient",
        "psychologist",
        "both",
        "unknown",
        name="missedby"
    )
    missedby_enum.create(op.get_bind(), checkfirst=True)

    
    op.add_column(
        "appointments",
        sa.Column("missed_by", missedby_enum, nullable=True)
    )


def downgrade() -> None:
    
    op.drop_column("appointments", "missed_by")

    
    sa.Enum(name="missedby").drop(op.get_bind(), checkfirst=True)
