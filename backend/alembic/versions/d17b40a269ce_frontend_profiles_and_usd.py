"""Profile photos and USD pricing; historical payments remain unchanged."""

import sqlalchemy as sa
from alembic import op

revision = "d17b40a269ce"
down_revision = "b07625e126ed"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("users", sa.Column("avatar_filename", sa.String(64), nullable=True))
    op.alter_column(
        "billing_psychologists",
        "hourly_net_minor",
        existing_type=sa.BigInteger(),
        nullable=True,
    )
    # A RUB amount is not a USD amount. Retain provider accounts but require a new rate.
    op.execute(
        "UPDATE billing_psychologists SET hourly_net_minor = NULL, currency = 'USD' WHERE currency <> 'USD'"
    )
    op.add_column(
        "billing_pricing_policies", sa.Column("currency", sa.String(3), nullable=True)
    )
    # Existing policies were denominated in RUB (including their fixed fees).
    op.execute("UPDATE billing_pricing_policies SET currency = 'RUB'")
    op.alter_column("billing_pricing_policies", "currency", nullable=False)


def downgrade():
    # Do not invent a replacement rate when rolling back a reset account.
    op.alter_column(
        "billing_psychologists",
        "hourly_net_minor",
        existing_type=sa.BigInteger(),
        nullable=False,
    )
    op.drop_column("billing_pricing_policies", "currency")
    op.drop_column("users", "avatar_filename")
