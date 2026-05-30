"""update slot events

Revision ID: ad46a0b2e53f
Revises: 20181e61b4fd
Create Date: 2026-05-19 20:17:11.842704

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'ad46a0b2e53f'
down_revision: Union[str, Sequence[str], None] = '20181e61b4fd'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute("ALTER TYPE slot_event_type ADD VALUE IF NOT EXISTS 'created'")
    op.execute("ALTER TYPE slot_event_type ADD VALUE IF NOT EXISTS 'removed'")

    op.add_column(
        "slot_events",
        sa.Column("performed_by_id", sa.UUID(), nullable=True),
    )

    op.create_index(
        op.f("ix_slot_events_performed_by_id"),
        "slot_events",
        ["performed_by_id"],
        unique=False,
    )

    op.create_foreign_key(
        "fk_slot_events_performed_by_id_users",
        "slot_events",
        "users",
        ["performed_by_id"],
        ["id"],
        ondelete="SET NULL",
    )


def downgrade() -> None:
    op.drop_constraint(
        "fk_slot_events_performed_by_id_users",
        "slot_events",
        type_="foreignkey",
    )

    op.drop_index(
        op.f("ix_slot_events_performed_by_id"),
        table_name="slot_events",
    )

    op.drop_column("slot_events", "performed_by_id")
