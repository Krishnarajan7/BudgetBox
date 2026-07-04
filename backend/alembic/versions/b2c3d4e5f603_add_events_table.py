"""add events table

Revision ID: b2c3d4e5f603
Revises: b2c3d4e5f602
Create Date: 2026-07-04 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "b2c3d4e5f603"
down_revision: Union[str, None] = "b2c3d4e5f602"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "events",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("title", sa.String(length=255), nullable=False),
        sa.Column("date", sa.Date(), nullable=False),
        sa.Column("time", sa.String(length=5), nullable=True),
        sa.Column(
            "kind",
            sa.String(length=20),
            nullable=False,
            server_default="event",
        ),
        sa.Column("note", sa.String(length=500), nullable=True),
        sa.Column(
            "recur_yearly",
            sa.Boolean(),
            server_default="false",
            nullable=False,
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.CheckConstraint(
            "kind IN ('event','birthday','anniversary','reminder','important_date')",
            name="ck_events_kind",
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_events_user_id_date",
        "events",
        ["user_id", "date"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_events_user_id_date", table_name="events")
    op.drop_table("events")
