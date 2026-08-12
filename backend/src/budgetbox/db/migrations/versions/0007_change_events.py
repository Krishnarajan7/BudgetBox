"""append-only sync change events with deletion tombstones

Revision ID: 0007
Revises: 0006
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0007"
down_revision: str | None = "0006"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


# (table, resource, primary-key SQL expression). All ids are text on the wire,
# including day keys and settings keys.
_TRACKED = (
    ("accounts", "accounts", "id"),
    ("balance_anchors", "balance_anchors", "id"),
    ("categories", "categories", "id"),
    ("txns", "txns", "id"),
    ("pinneds", "pinned", "id"),
    ("day_seals", "day_seals", "date"),
    ("settings", "settings", "key"),
    ("recurrings", "recurrings", "id"),
    ("budgets", "budgets", "id"),
    ("goals", "goals", "id"),
    ("notes", "notes", "id"),
    ("focus_sessions", "focus_sessions", "id"),
    ("journal_entries", "journal_entries", "date"),
    ("events", "events", "id"),
    ("vault_items", "vault_items", "id"),
)

_NOW = "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')"


def _trigger_name(table: str, suffix: str) -> str:
    return f"trg_sync_{table}_{suffix}"


def upgrade() -> None:
    op.create_table(
        "change_events",
        sa.Column("sequence", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("resource", sa.String(length=40), nullable=False),
        sa.Column("resource_id", sa.String(length=40), nullable=False),
        sa.Column(
            "operation",
            sa.Enum(
                "upsert",
                "delete",
                name="change_operation",
                native_enum=False,
                create_constraint=True,
                length=24,
            ),
            nullable=False,
        ),
        sa.Column("changed_at", sa.String(length=32), nullable=False),
        sa.PrimaryKeyConstraint("sequence", name=op.f("pk_change_events")),
    )
    op.create_index(op.f("ix_change_events_resource"), "change_events", ["resource"], unique=False)

    for table, resource, key in _TRACKED:
        # Existing rows become the initial snapshot for a new cursor-based
        # client. Later mutations are captured by the triggers below.
        op.execute(
            sa.text(
                f"INSERT INTO change_events "
                f"(resource, resource_id, operation, changed_at) "
                f"SELECT :resource, CAST({key} AS TEXT), 'upsert', {_NOW} FROM {table}"
            ).bindparams(resource=resource)
        )
        op.execute(
            f"CREATE TRIGGER {_trigger_name(table, 'insert')} "
            f"AFTER INSERT ON {table} BEGIN "
            f"INSERT INTO change_events (resource, resource_id, operation, changed_at) "
            f"VALUES ('{resource}', CAST(NEW.{key} AS TEXT), 'upsert', {_NOW}); END"
        )
        op.execute(
            f"CREATE TRIGGER {_trigger_name(table, 'update')} "
            f"AFTER UPDATE ON {table} BEGIN "
            f"INSERT INTO change_events (resource, resource_id, operation, changed_at) "
            f"VALUES ('{resource}', CAST(NEW.{key} AS TEXT), 'upsert', {_NOW}); END"
        )
        op.execute(
            f"CREATE TRIGGER {_trigger_name(table, 'delete')} "
            f"AFTER DELETE ON {table} BEGIN "
            f"INSERT INTO change_events (resource, resource_id, operation, changed_at) "
            f"VALUES ('{resource}', CAST(OLD.{key} AS TEXT), 'delete', {_NOW}); END"
        )


def downgrade() -> None:
    for table, _resource, _key in reversed(_TRACKED):
        for suffix in ("delete", "update", "insert"):
            op.execute(f"DROP TRIGGER IF EXISTS {_trigger_name(table, suffix)}")
    op.drop_index(op.f("ix_change_events_resource"), table_name="change_events")
    op.drop_table("change_events")
