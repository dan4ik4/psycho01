"""add psychologist rating range constraint

Revision ID: 821ad6462f00
Revises: 9149c56f552b
Create Date: 2026-08-19 17:08:01.491142

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '821ad6462f00'
down_revision: Union[str, Sequence[str], None] = '9149c56f552b'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    connection = op.get_bind()

    invalid_rating = connection.execute(
        sa.text(
            """
            SELECT id, rating
            FROM psychologist_ratings
            WHERE rating < 1 OR rating > 5
            LIMIT 1
            """
        )
    ).first()

    if invalid_rating is not None:
        rating_id, rating = invalid_rating

        raise RuntimeError(
            "Invalid psychologist rating found: "
            f"id={rating_id}, rating={rating}"
        )

    op.create_check_constraint(
        "ck_psychologist_ratings_rating_range",
        "psychologist_ratings",
        "rating >= 1 AND rating <= 5",
    )


def downgrade() -> None:
    op.drop_constraint(
        "ck_psychologist_ratings_rating_range",
        "psychologist_ratings",
        type_="check",
    )
