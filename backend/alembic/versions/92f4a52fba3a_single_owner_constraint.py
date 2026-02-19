"""single owner constraint

Revision ID: 92f4a52fba3a
Revises: db3285631796
Create Date: 2026-02-17 19:38:08.189775

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '92f4a52fba3a'
down_revision: Union[str, Sequence[str], None] = 'db3285631796'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_index(
        "uq_single_owner",
        "users",
        ["role"],
        unique=True,
        postgresql_where=sa.text("role = 'owner'"),
    )


def downgrade() -> None:
    op.drop_index("uq_single_owner", table_name="users")
