"""the check-in's second breath: why the day sat that way, and its context

Revision ID: 0011
Revises: 0010
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0011"
down_revision: str | None = "0010"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # Plain add_column — no table rebuild, so 0007's sync triggers stay put.
    op.add_column("journal_entries", sa.Column("feel_why", sa.Text(), nullable=True))
    op.add_column("journal_entries", sa.Column("feel_tags", sa.Text(), nullable=True))


def downgrade() -> None:
    with op.batch_alter_table("journal_entries", schema=None) as batch_op:
        batch_op.drop_column("feel_tags")
        batch_op.drop_column("feel_why")
    # Batch rebuilds the table and SQLite drops its triggers with it.
    _now = "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')"
    for suffix, event, row in (("insert", "INSERT", "NEW"), ("update", "UPDATE", "NEW")):
        op.execute(
            f"CREATE TRIGGER trg_sync_journal_entries_{suffix} "
            f"AFTER {event} ON journal_entries BEGIN "
            f"INSERT INTO change_events (resource, resource_id, operation, changed_at) "
            f"VALUES ('journal_entries', CAST({row}.date AS TEXT), 'upsert', {_now}); END"
        )
    op.execute(
        "CREATE TRIGGER trg_sync_journal_entries_delete "
        "AFTER DELETE ON journal_entries BEGIN "
        "INSERT INTO change_events (resource, resource_id, operation, changed_at) "
        f"VALUES ('journal_entries', CAST(OLD.date AS TEXT), 'delete', {_now}); END"
    )
