"""add overlapping constraint for slots

Revision ID: 4fef5c9b2284
Revises: 4790a0ae6357
Create Date: 2026-03-14 17:39:09.241236

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '4fef5c9b2284'
down_revision: Union[str, Sequence[str], None] = '4790a0ae6357'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute("CREATE EXTENSION IF NOT EXISTS btree_gist;")

    op.execute(
        """
        ALTER TABLE availability_slots
        ADD CONSTRAINT no_overlapping_psychologist_slots
        EXCLUDE USING gist (
            psychologist_id WITH =,
            tstzrange(start_at, end_at, '[)') WITH &&
        );
        """
    )
    pass


def downgrade() -> None:
    op.execute(
        """
        ALTER TABLE availability_slots
        DROP CONSTRAINT IF EXISTS no_overlapping_psychologist_slots;
        """
    )
    pass
