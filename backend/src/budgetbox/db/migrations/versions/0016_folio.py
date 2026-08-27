"""the folio — money moved out of a bank and into funds

Revision ID: 0016
Revises: 0015

Buying a fund is not spending: the money changes shape, not owner. Each
contribution is a transfer into the asset account the setup ritual already
calls 'SIP / mutual funds', so a month of SIPs never reads as a blown budget.

A holding keeps units rather than a rupee figure, because what a fund is worth
moves on its own. Units times the latest AMFI NAV is the value; what was paid
in is the cost; the gap is the only return figure this book shows.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0016"
down_revision: str | None = "0015"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_NOW = "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')"
_TRACKED = (("funds", "fund", "id"), ("folio_entries", "folio_entry", "id"))


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
        "funds",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("name", sa.String(160), nullable=False),
        sa.Column("scheme_code", sa.String(12), nullable=True),
        sa.Column("nav", sa.Float(), nullable=True),
        sa.Column("nav_date", sa.String(10), nullable=True),
        sa.Column("manual_value_paise", sa.Integer, nullable=True),
        sa.Column("manual_value_at", sa.String(32), nullable=True),
        sa.Column("note", sa.Text, nullable=True),
        sa.Column("archived", sa.Boolean, nullable=False, server_default=sa.text("0")),
        sa.Column("sort_order", sa.Integer, nullable=False, server_default=sa.text("0")),
        sa.Column("created_at", sa.String(32), nullable=False),
        sa.Column("updated_at", sa.String(32), nullable=False),
    )
    op.create_index("ix_funds_scheme_code", "funds", ["scheme_code"])
    op.create_table(
        "folio_entries",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column(
            "fund_id",
            sa.String(36),
            sa.ForeignKey("funds.id", name="fk_folio_entries_fund_id_funds"),
            nullable=False,
        ),
        sa.Column(
            "kind",
            sa.Enum(
                "sip",
                "lumpsum",
                "redeem",
                name="folio_entry_kind",
                native_enum=False,
                create_constraint=True,
                length=24,
            ),
            nullable=False,
        ),
        sa.Column("amount_paise", sa.Integer, nullable=False),
        sa.Column("units", sa.Numeric(20, 5), nullable=True),
        sa.Column("nav", sa.Float(), nullable=True),
        sa.Column("at", sa.String(32), nullable=False),
        sa.Column("note", sa.Text, nullable=True),
        sa.Column(
            "txn_id",
            sa.String(36),
            sa.ForeignKey("txns.id", name="fk_folio_entries_txn_id_txns"),
            nullable=True,
        ),
        sa.Column("created_at", sa.String(32), nullable=False),
        sa.Column("updated_at", sa.String(32), nullable=False),
        sa.CheckConstraint("amount_paise > 0", name="ck_folio_entries_amount_positive"),
    )
    op.create_index("ix_folio_entries_fund_at", "folio_entries", ["fund_id", "at"])
    for table, resource, key in _TRACKED:
        _sync_triggers(table, resource, key)


def downgrade() -> None:
    for table, _, _ in _TRACKED:
        for suffix in ("insert", "update", "delete"):
            op.execute(f"DROP TRIGGER IF EXISTS trg_sync_{table}_{suffix}")
    op.drop_table("folio_entries")
    op.drop_table("funds")
