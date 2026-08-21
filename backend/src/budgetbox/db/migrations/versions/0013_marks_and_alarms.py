"""the day's marks and the alarms — the two books that never left the phone

Revision ID: 0013
Revises: 0012

Habits, meals, slips and alarms were device-local, which meant a reinstall
lost the clean streak and every morning. Both tables land here, tracked by
the same change_events triggers as everything else so a restoring phone
pulls them down whole. Habit *definitions* need no table: they already live
in `settings` under 'habits', which syncs.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0013"
down_revision: str | None = "0012"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_NOW = "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')"
_TRACKED = (("day_marks", "day_marks", "id"), ("alarms", "alarms", "id"))


def _sync_triggers(table: str, resource: str, key: str) -> None:
    for suffix, event, row in (
        ("insert", "INSERT", "NEW"),
        ("update", "UPDATE", "NEW"),
        ("delete", "DELETE", "OLD"),
    ):
        operation = "delete" if suffix == "delete" else "upsert"
        op.execute(
            f"CREATE TRIGGER trg_sync_{table}_{suffix} "
            f"AFTER {event} ON {table} BEGIN "
            f"INSERT INTO change_events (resource, resource_id, operation, changed_at) "
            f"VALUES ('{resource}', CAST({row}.{key} AS TEXT), '{operation}', {_NOW}); END"
        )


def upgrade() -> None:
    op.create_table(
        "day_marks",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("date", sa.String(length=10), nullable=False),
        sa.Column("kind", sa.String(length=32), nullable=False),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("at", sa.String(length=32), nullable=False),
        sa.Column("created_at", sa.String(length=32), nullable=False),
        sa.Column("updated_at", sa.String(length=32), nullable=False),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_day_marks")),
    )
    with op.batch_alter_table("day_marks", schema=None) as batch_op:
        batch_op.create_index(op.f("ix_day_marks_date"), ["date"], unique=False)

    op.create_table(
        "alarms",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("label", sa.String(length=60), nullable=False),
        sa.Column("minute_of_day", sa.Integer(), nullable=False),
        sa.Column("days", sa.Integer(), nullable=False),
        sa.Column("enabled", sa.Boolean(), nullable=False),
        sa.Column("snooze_minutes", sa.Integer(), nullable=False),
        sa.Column("vibrate", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.String(length=32), nullable=False),
        sa.Column("updated_at", sa.String(length=32), nullable=False),
        sa.CheckConstraint("minute_of_day BETWEEN 0 AND 1439", name=op.f("ck_alarms_minute_range")),
        sa.CheckConstraint("days BETWEEN 0 AND 127", name=op.f("ck_alarms_days_mask")),
        sa.CheckConstraint("snooze_minutes BETWEEN 1 AND 60", name=op.f("ck_alarms_snooze_range")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_alarms")),
    )

    for table, resource, key in _TRACKED:
        _sync_triggers(table, resource, key)


def downgrade() -> None:
    for table, _resource, _key in reversed(_TRACKED):
        for suffix in ("delete", "update", "insert"):
            op.execute(f"DROP TRIGGER IF EXISTS trg_sync_{table}_{suffix}")
    op.drop_table("alarms")
    with op.batch_alter_table("day_marks", schema=None) as batch_op:
        batch_op.drop_index(op.f("ix_day_marks_date"))
    op.drop_table("day_marks")
