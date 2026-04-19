"""add join/leave timestamps to appointments

Revision ID: 2b2de9c8719a
Revises: 4125747559c1
Create Date: 2026-04-11 17:04:42.186939

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '2b2de9c8719a'
down_revision: Union[str, Sequence[str], None] = '4125747559c1'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "appointments",
        sa.Column("patient_joined_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "appointments",
        sa.Column("patient_left_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "appointments",
        sa.Column("psychologist_joined_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "appointments",
        sa.Column("psychologist_left_at", sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("appointments", "psychologist_left_at")
    op.drop_column("appointments", "psychologist_joined_at")
    op.drop_column("appointments", "patient_left_at")
    op.drop_column("appointments", "patient_joined_at")
