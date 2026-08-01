"""budgets (+hand-picked txn links) and goals; txns.goal_id gains its FK

Revision ID: 0004
Revises: 0003
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0004"
down_revision: str | None = "0003"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "goals",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("name", sa.String(length=60), nullable=False),
        sa.Column("target_paise", sa.Integer(), nullable=False),
        sa.Column(
            "kind",
            sa.Enum(
                "save",
                "clear",
                name="goal_kind",
                native_enum=False,
                create_constraint=True,
                length=24,
            ),
            nullable=False,
        ),
        sa.Column("target_date", sa.String(length=10), nullable=True),
        sa.Column("monthly_paise", sa.Integer(), nullable=True),
        sa.Column("archived", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.String(length=32), nullable=False),
        sa.Column("updated_at", sa.String(length=32), nullable=False),
        sa.CheckConstraint("target_paise > 0", name=op.f("ck_goals_target_positive")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_goals")),
    )
    op.create_table(
        "budgets",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("category_id", sa.String(length=36), nullable=True),
        sa.Column("name", sa.String(length=60), nullable=False),
        sa.Column("limit_paise", sa.Integer(), nullable=False),
        sa.Column(
            "period",
            sa.Enum(
                "month",
                "fy",
                "custom",
                name="budget_period",
                native_enum=False,
                create_constraint=True,
                length=24,
            ),
            nullable=False,
        ),
        sa.Column(
            "kind",
            sa.Enum(
                "all",
                "added",
                name="budget_kind",
                native_enum=False,
                create_constraint=True,
                length=24,
            ),
            nullable=False,
        ),
        sa.Column("rollover", sa.Boolean(), nullable=False),
        sa.Column("archived", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.String(length=32), nullable=False),
        sa.Column("updated_at", sa.String(length=32), nullable=False),
        sa.CheckConstraint("limit_paise > 0", name=op.f("ck_budgets_limit_positive")),
        sa.ForeignKeyConstraint(
            ["category_id"], ["categories.id"], name=op.f("fk_budgets_category_id_categories")
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_budgets")),
    )
    op.create_table(
        "budget_txns",
        sa.Column("budget_id", sa.String(length=36), nullable=False),
        sa.Column("txn_id", sa.String(length=36), nullable=False),
        sa.Column("created_at", sa.String(length=32), nullable=False),
        sa.Column("updated_at", sa.String(length=32), nullable=False),
        sa.ForeignKeyConstraint(
            ["budget_id"], ["budgets.id"], name=op.f("fk_budget_txns_budget_id_budgets")
        ),
        sa.ForeignKeyConstraint(
            ["txn_id"], ["txns.id"], name=op.f("fk_budget_txns_txn_id_txns"), ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("budget_id", "txn_id", name=op.f("pk_budget_txns")),
    )
    with op.batch_alter_table("txns", schema=None) as batch_op:
        batch_op.create_foreign_key(
            batch_op.f("fk_txns_goal_id_goals"), "goals", ["goal_id"], ["id"]
        )


def downgrade() -> None:
    with op.batch_alter_table("txns", schema=None) as batch_op:
        batch_op.drop_constraint(batch_op.f("fk_txns_goal_id_goals"), type_="foreignkey")
    op.drop_table("budget_txns")
    op.drop_table("budgets")
    op.drop_table("goals")
