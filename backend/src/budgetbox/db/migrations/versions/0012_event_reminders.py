"""an event can carry its owner's asked-for reminder time

Revision ID: 0012
Revises: 0011
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0012"
down_revision: str | None = "0011"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # Plain add_column — no table rebuild, so the sync triggers stay put.
    # The range check joins on the next full rebuild; SQLite cannot add a
    # table constraint in place and a rebuild would drop the triggers.
    op.add_column("events", sa.Column("remind_minutes", sa.Integer(), nullable=True))


def downgrade() -> None:
    with op.batch_alter_table("events", schema=None) as batch_op:
        batch_op.drop_column("remind_minutes")
    # Batch rebuilds the table and SQLite drops its triggers with it.
    _now = "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')"
    for suffix, event, row in (("insert", "INSERT", "NEW"), ("update", "UPDATE", "NEW")):
        op.execute(
            f"CREATE TRIGGER trg_sync_events_{suffix} "
            f"AFTER {event} ON events BEGIN "
            f"INSERT INTO change_events (resource, resource_id, operation, changed_at) "
            f"VALUES ('events', CAST({row}.id AS TEXT), 'upsert', {_now}); END"
        )
    op.execute(
        "CREATE TRIGGER trg_sync_events_delete "
        "AFTER DELETE ON events BEGIN "
        "INSERT INTO change_events (resource, resource_id, operation, changed_at) "
        f"VALUES ('events', CAST(OLD.id AS TEXT), 'delete', {_now}); END"
    )
