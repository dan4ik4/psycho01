"""allow repeated patient psychologist assignments

Revision ID: 44752d9c4ff7
Revises: cb91d3d03270
Create Date: 2026-08-20 13:30:49.731266

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '44752d9c4ff7'
down_revision: Union[str, Sequence[str], None] = 'cb91d3d03270'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.drop_constraint(
        "uq_patient_assignments_patient_psychologist",
        "patient_assignments",
        type_="unique",
    )


def downgrade() -> None:
    op.create_unique_constraint(
        "uq_patient_assignments_patient_psychologist",
        "patient_assignments",
        ["patient_id", "psychologist_id"],
    )
