"""add slot minimum duration constraint

Revision ID: cb91d3d03270
Revises: 821ad6462f00
Create Date: 2026-08-19 17:11:28.370028

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'cb91d3d03270'
down_revision: Union[str, Sequence[str], None] = '821ad6462f00'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    connection = op.get_bind()

    invalid_slot = connection.execute(
        sa.text(
            """
            SELECT id, start_at, end_at
            FROM slots
            WHERE end_at < start_at + INTERVAL '15 minutes'
            LIMIT 1
            """
        )
    ).first()

    if invalid_slot is not None:
        slot_id, start_at, end_at = invalid_slot

        raise RuntimeError(
            "Invalid slot duration found: "
            f"id={slot_id}, start_at={start_at}, end_at={end_at}"
        )

    op.create_check_constraint(
        "ck_slots_minimum_duration",
        "slots",
        "end_at >= start_at + INTERVAL '15 minutes'",
    )


def downgrade() -> None:
    op.drop_constraint(
        "ck_slots_minimum_duration",
        "slots",
        type_="check",
    )
