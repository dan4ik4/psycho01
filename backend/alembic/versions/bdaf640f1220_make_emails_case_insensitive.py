"""make emails case insensitive

Revision ID: bdaf640f1220
Revises: 11c35ca20c2c
Create Date: 2026-08-14 14:30:35.166555

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'bdaf640f1220'
down_revision: Union[str, Sequence[str], None] = '11c35ca20c2c'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    connection = op.get_bind()

    duplicate_user_email = connection.execute(
        sa.text(
            """
            SELECT lower(email)
            FROM users
            GROUP BY lower(email)
            HAVING count(*) > 1
            LIMIT 1
            """
        )
    ).scalar_one_or_none()

    if duplicate_user_email is not None:
        raise RuntimeError(
            "Case-insensitive duplicate found in users: "
            f"{duplicate_user_email}"
        )

    duplicate_pending_email = connection.execute(
        sa.text(
            """
            SELECT lower(email)
            FROM pending_registrations
            GROUP BY lower(email)
            HAVING count(*) > 1
            LIMIT 1
            """
        )
    ).scalar_one_or_none()

    if duplicate_pending_email is not None:
        raise RuntimeError(
            "Case-insensitive duplicate found in pending_registrations: "
            f"{duplicate_pending_email}"
        )

    op.execute(
        sa.text(
            """
            UPDATE users
            SET email = lower(email)
            WHERE email <> lower(email)
            """
        )
    )

    op.execute(
        sa.text(
            """
            UPDATE pending_registrations
            SET email = lower(email)
            WHERE email <> lower(email)
            """
        )
    )

    op.create_index(
        "ux_users_email_lower",
        "users",
        [sa.text("lower(email)")],
        unique=True,
    )

    op.create_index(
        "ux_pending_registrations_email_lower",
        "pending_registrations",
        [sa.text("lower(email)")],
        unique=True,
    )


def downgrade() -> None:
    op.drop_index(
        "ux_pending_registrations_email_lower",
        table_name="pending_registrations",
    )

    op.drop_index(
        "ux_users_email_lower",
        table_name="users",
    )
