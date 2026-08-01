"""recurrings + job_runs; txns.recurring_id gains its FK and the one-txn-per-due
uniqueness guard

Revision ID: 0003
Revises: 0002
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0003"
down_revision: str | None = "0002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "recurrings",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("title", sa.String(length=120), nullable=False),
        sa.Column("amount_paise", sa.Integer(), nullable=False),
        sa.Column("category_id", sa.String(length=36), nullable=True),
        sa.Column("account_id", sa.String(length=36), nullable=False),
        sa.Column(
            "kind",
            sa.Enum(
                "bill",
                "subscription",
                name="recurring_kind",
                native_enum=False,
                create_constraint=True,
                length=24,
            ),
            nullable=False,
        ),
        sa.Column("every_months", sa.Integer(), nullable=False),
        sa.Column("day_of_month", sa.Integer(), nullable=False),
        sa.Column("next_due", sa.String(length=10), nullable=False),
        sa.Column("active", sa.Boolean(), nullable=False),
        sa.Column("last_materialized_due", sa.String(length=10), nullable=True),
        sa.Column("created_at", sa.String(length=32), nullable=False),
        sa.Column("updated_at", sa.String(length=32), nullable=False),
        sa.CheckConstraint("every_months >= 1", name=op.f("ck_recurrings_every_months_positive")),
        sa.CheckConstraint(
            "day_of_month BETWEEN 1 AND 31", name=op.f("ck_recurrings_day_of_month_range")
        ),
        sa.CheckConstraint("amount_paise > 0", name=op.f("ck_recurrings_amount_positive")),
        sa.ForeignKeyConstraint(
            ["account_id"], ["accounts.id"], name=op.f("fk_recurrings_account_id_accounts")
        ),
        sa.ForeignKeyConstraint(
            ["category_id"], ["categories.id"], name=op.f("fk_recurrings_category_id_categories")
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_recurrings")),
    )
    op.create_table(
        "job_runs",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("name", sa.String(length=40), nullable=False),
        sa.Column("started_at", sa.String(length=32), nullable=False),
        sa.Column("finished_at", sa.String(length=32), nullable=True),
        sa.Column("ok", sa.Boolean(), nullable=False),
        sa.Column("detail", sa.String(length=500), nullable=True),
        sa.Column("created_at", sa.String(length=32), nullable=False),
        sa.Column("updated_at", sa.String(length=32), nullable=False),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_job_runs")),
    )
    with op.batch_alter_table("txns", schema=None) as batch_op:
        batch_op.create_foreign_key(
            batch_op.f("fk_txns_recurring_id_recurrings"), "recurrings", ["recurring_id"], ["id"]
        )
    op.create_index(
        "uq_txns_recurring_due",
        "txns",
        ["recurring_id", "at"],
        unique=True,
        sqlite_where=sa.text("recurring_id IS NOT NULL"),
    )


def downgrade() -> None:
    op.drop_index("uq_txns_recurring_due", table_name="txns")
    with op.batch_alter_table("txns", schema=None) as batch_op:
        batch_op.drop_constraint(batch_op.f("fk_txns_recurring_id_recurrings"), type_="foreignkey")
    op.drop_table("job_runs")
    op.drop_table("recurrings")
