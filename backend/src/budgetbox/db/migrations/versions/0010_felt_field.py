"""the felt field: mood widens to pleasantness 1-9, gains energy and the word

Revision ID: 0010
Revises: 0009
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0010"
down_revision: str | None = "0009"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_NOW = "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')"


def _recreate_sync_triggers() -> None:
    """Batch-alter rebuilds journal_entries, and SQLite drops a table's triggers
    with the table — put 0007's change-event triggers back."""
    for suffix, event, row in (("insert", "INSERT", "NEW"), ("update", "UPDATE", "NEW")):
        op.execute(
            f"CREATE TRIGGER trg_sync_journal_entries_{suffix} "
            f"AFTER {event} ON journal_entries BEGIN "
            f"INSERT INTO change_events (resource, resource_id, operation, changed_at) "
            f"VALUES ('journal_entries', CAST({row}.date AS TEXT), 'upsert', {_NOW}); END"
        )
    op.execute(
        "CREATE TRIGGER trg_sync_journal_entries_delete "
        "AFTER DELETE ON journal_entries BEGIN "
        "INSERT INTO change_events (resource, resource_id, operation, changed_at) "
        f"VALUES ('journal_entries', CAST(OLD.date AS TEXT), 'delete', {_NOW}); END"
    )


def upgrade() -> None:
    # Widen the check first (the old 1-5 values satisfy 1-9), then re-rule the
    # recorded moods onto the wider scale so an old 3 stays to-day's 5.
    with op.batch_alter_table("journal_entries", schema=None) as batch_op:
        batch_op.add_column(sa.Column("energy", sa.Integer(), nullable=True))
        batch_op.add_column(sa.Column("feel_word", sa.Text(), nullable=True))
        batch_op.drop_constraint(batch_op.f("ck_journal_entries_mood_range"), type_="check")
        batch_op.create_check_constraint("mood_range", "mood IS NULL OR mood BETWEEN 1 AND 9")
        batch_op.create_check_constraint("energy_range", "energy IS NULL OR energy BETWEEN 1 AND 9")
    _recreate_sync_triggers()
    op.execute(
        "UPDATE journal_entries SET mood = (mood - 1) * 2 + 1 WHERE mood IS NOT NULL AND mood <= 5"
    )


def downgrade() -> None:
    op.execute("UPDATE journal_entries SET mood = (mood - 1) / 2 + 1 WHERE mood IS NOT NULL")
    with op.batch_alter_table("journal_entries", schema=None) as batch_op:
        batch_op.drop_constraint(batch_op.f("ck_journal_entries_energy_range"), type_="check")
        batch_op.drop_constraint(batch_op.f("ck_journal_entries_mood_range"), type_="check")
        batch_op.create_check_constraint("mood_range", "mood IS NULL OR mood BETWEEN 1 AND 5")
        batch_op.drop_column("feel_word")
        batch_op.drop_column("energy")
    _recreate_sync_triggers()
