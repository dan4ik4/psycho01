"""add unique patient assignment pair

Revision ID: 9149c56f552b
Revises: bdaf640f1220
Create Date: 2026-08-19 17:04:25.107096

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '9149c56f552b'
down_revision: Union[str, Sequence[str], None] = 'bdaf640f1220'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    connection = op.get_bind()

    duplicate_pair = connection.execute(
        sa.text(
            """
            SELECT patient_id, psychologist_id
            FROM patient_assignments
            GROUP BY patient_id, psychologist_id
            HAVING count(*) > 1
            LIMIT 1
            """
        )
    ).first()

    if duplicate_pair is not None:
        patient_id, psychologist_id = duplicate_pair

        raise RuntimeError(
            "Duplicate patient assignment pair found: "
            f"patient_id={patient_id}, "
            f"psychologist_id={psychologist_id}"
        )

    op.create_unique_constraint(
        "uq_patient_assignments_patient_psychologist",
        "patient_assignments",
        ["patient_id", "psychologist_id"],
    )


def downgrade() -> None:
    op.drop_constraint(
        "uq_patient_assignments_patient_psychologist",
        "patient_assignments",
        type_="unique",
    )
