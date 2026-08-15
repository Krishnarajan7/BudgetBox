"""actionable notes with reminder times and completion

Revision ID: 0009
Revises: 0008
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0009"
down_revision: str | None = "0008"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("notes", sa.Column("remind_at", sa.String(length=32), nullable=True))
    op.add_column(
        "notes",
        sa.Column("completed", sa.Boolean(), server_default=sa.false(), nullable=False),
    )


def downgrade() -> None:
    op.drop_column("notes", "completed")
    op.drop_column("notes", "remind_at")
