"""account_snapshots: end-of-day balance history behind the net worth chart

Revision ID: 0005
Revises: 0004
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0005"
down_revision: str | None = "0004"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "account_snapshots",
        sa.Column("account_id", sa.String(length=36), nullable=False),
        sa.Column("date", sa.String(length=10), nullable=False),
        sa.Column("balance_paise", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.String(length=32), nullable=False),
        sa.Column("updated_at", sa.String(length=32), nullable=False),
        sa.ForeignKeyConstraint(
            ["account_id"], ["accounts.id"], name=op.f("fk_account_snapshots_account_id_accounts")
        ),
        sa.PrimaryKeyConstraint("account_id", "date", name=op.f("pk_account_snapshots")),
    )


def downgrade() -> None:
    op.drop_table("account_snapshots")
