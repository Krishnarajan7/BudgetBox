"""the slate — money lent, and money that came back

Revision ID: 0015
Revises: 0014

Lending is not spending: the money is still yours, only out of reach. Each
entry moves real money as a transfer between a pocket and one asset account
('On the slate', created on first use), so spending stays honest and net
worth stays flat until a loan is actually let go.

Tracked by the change_events triggers like every other synced book, so a
restoring phone pulls the slate down whole.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0015"
down_revision: str | None = "0014"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_NOW = "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')"
_TRACKED = (
    ("slate_people", "slate_person", "id"),
    ("slate_entries", "slate_entry", "id"),
)


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
        "slate_people",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("name", sa.String(60), nullable=False),
        sa.Column("relation", sa.String(40), nullable=True),
        sa.Column("note", sa.Text, nullable=True),
        sa.Column("archived", sa.Boolean, nullable=False, server_default=sa.text("0")),
        sa.Column("created_at", sa.String(32), nullable=False),
        sa.Column("updated_at", sa.String(32), nullable=False),
    )
    op.create_index("ix_slate_people_name", "slate_people", ["name"])
    op.create_table(
        "slate_entries",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column(
            "person_id",
            sa.String(36),
            sa.ForeignKey("slate_people.id", name="fk_slate_entries_person_id_slate_people"),
            nullable=False,
        ),
        sa.Column(
            "kind",
            sa.Enum(
                "lent",
                "repaid",
                "borrowed",
                "settled",
                "forgiven",
                "written_off",
                name="slate_kind",
                native_enum=False,
                create_constraint=True,
                length=24,
            ),
            nullable=False,
        ),
        sa.Column("amount_paise", sa.Integer, nullable=False),
        sa.Column("at", sa.String(32), nullable=False),
        sa.Column("note", sa.Text, nullable=True),
        sa.Column(
            "txn_id",
            sa.String(36),
            sa.ForeignKey("txns.id", name="fk_slate_entries_txn_id_txns"),
            nullable=True,
        ),
        sa.Column("created_at", sa.String(32), nullable=False),
        sa.Column("updated_at", sa.String(32), nullable=False),
        sa.CheckConstraint("amount_paise > 0", name="ck_slate_entries_amount_positive"),
    )
    op.create_index("ix_slate_entries_person_at", "slate_entries", ["person_id", "at"])
    for table, resource, key in _TRACKED:
        _sync_triggers(table, resource, key)


def downgrade() -> None:
    for table, _, _ in _TRACKED:
        for suffix in ("insert", "update", "delete"):
            op.execute(f"DROP TRIGGER IF EXISTS trg_sync_{table}_{suffix}")
    op.drop_table("slate_entries")
    op.drop_table("slate_people")
