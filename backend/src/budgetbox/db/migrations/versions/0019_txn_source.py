"""every expense can name the pot of income it drew on

Revision ID: 0019
Revises: 0018

Money sits in accounts, but it also belongs to where it came from: the
salary, the extra work. An expense's source_id points at that income
category, so "what did I spend from salary and what is left of it" has an
answer without the money ever being split across accounts. Nullable: the
lines written before the phone asked stay as they are.
"""

from collections.abc import Sequence

from alembic import op

revision: str = "0019"
down_revision: str | None = "0018"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # A plain ADD COLUMN, deliberately: a batch rebuild copies the table
    # and drops the change_events triggers on it with the old one, and the
    # phones would stop hearing about their own lines. SQLite adds a
    # nullable REFERENCES column in place; Alembic's SQLite dialect refuses
    # to emit the constraint, so the statement is written out by hand.
    op.execute("ALTER TABLE txns ADD COLUMN source_id VARCHAR(36) REFERENCES categories (id)")


def downgrade() -> None:
    with op.batch_alter_table("txns", schema=None) as batch_op:
        batch_op.drop_column("source_id")
