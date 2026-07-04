"""add user_id to categories

Revision ID: a1b2c3d4e5f6
Revises: 88cdc83bc37e
Create Date: 2026-05-26 22:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "a1b2c3d4e5f6"
down_revision: Union[str, None] = "88cdc83bc37e"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Existing categories rows have no owner; the service has always tried to
    # write user_id, so any rows in this table are inconsistent test data.
    # Clear them, then add the column as NOT NULL with FK + index.
    op.execute("DELETE FROM categories")

    op.add_column(
        "categories",
        sa.Column("user_id", sa.Integer(), nullable=False),
    )
    op.create_foreign_key(
        "fk_categories_user_id_users",
        "categories",
        "users",
        ["user_id"],
        ["id"],
        ondelete="CASCADE",
    )
    op.create_index(
        "ix_categories_user_id",
        "categories",
        ["user_id"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_categories_user_id", table_name="categories")
    op.drop_constraint("fk_categories_user_id_users", "categories", type_="foreignkey")
    op.drop_column("categories", "user_id")
