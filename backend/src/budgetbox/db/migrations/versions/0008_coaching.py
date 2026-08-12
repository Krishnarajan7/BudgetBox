"""merchant rules and evidence-backed coaching insights

Revision ID: 0008
Revises: 0007
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0008"
down_revision: str | None = "0007"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "merchant_rules",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("match_text", sa.String(length=120), nullable=False),
        sa.Column("merchant_name", sa.String(length=80), nullable=False),
        sa.Column(
            "classification",
            sa.Enum(
                "essential",
                "discretionary",
                "avoid",
                name="spending_class",
                native_enum=False,
                create_constraint=True,
                length=24,
            ),
            nullable=False,
        ),
        sa.Column("active", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.String(length=32), nullable=False),
        sa.Column("updated_at", sa.String(length=32), nullable=False),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_merchant_rules")),
        sa.UniqueConstraint("match_text", name=op.f("uq_merchant_rules_match_text")),
    )
    op.create_table(
        "coaching_insights",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("fingerprint", sa.String(length=160), nullable=False),
        sa.Column(
            "kind",
            sa.Enum(
                "merchant_surge",
                "repeated_discretionary",
                "budget_risk",
                name="insight_kind",
                native_enum=False,
                create_constraint=True,
                length=24,
            ),
            nullable=False,
        ),
        sa.Column("title", sa.String(length=120), nullable=False),
        sa.Column("message", sa.Text(), nullable=False),
        sa.Column("evidence_json", sa.Text(), nullable=False),
        sa.Column("priority", sa.Integer(), nullable=False),
        sa.Column("current_paise", sa.Integer(), nullable=True),
        sa.Column("baseline_paise", sa.Integer(), nullable=True),
        sa.Column("difference_paise", sa.Integer(), nullable=True),
        sa.Column("period_start", sa.String(length=10), nullable=False),
        sa.Column("period_end", sa.String(length=10), nullable=False),
        sa.Column("expires_on", sa.String(length=10), nullable=False),
        sa.Column(
            "status",
            sa.Enum(
                "active",
                "dismissed",
                "acted",
                name="insight_status",
                native_enum=False,
                create_constraint=True,
                length=24,
            ),
            nullable=False,
        ),
        sa.Column("snoozed_until", sa.String(length=10), nullable=True),
        sa.Column("created_at", sa.String(length=32), nullable=False),
        sa.Column("updated_at", sa.String(length=32), nullable=False),
        sa.CheckConstraint(
            "priority BETWEEN 0 AND 100", name=op.f("ck_coaching_insights_priority_range")
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_coaching_insights")),
        sa.UniqueConstraint("fingerprint", name=op.f("uq_coaching_insights_fingerprint")),
    )

def downgrade() -> None:
    op.drop_table("coaching_insights")
    op.drop_table("merchant_rules")
