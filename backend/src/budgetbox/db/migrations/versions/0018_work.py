"""the work book — clients, projects, quote revisions, project links

Revision ID: 0018
Revises: 0017

Freelance money has two shapes the ledger alone loses: a quote that moves
(50k, then 40k when the scope shrank) and costs a project causes that must
not be forgotten at invoice time. Projects hold the quote as it stands,
quote_revisions hold how it got there, and project_links claim ledger lines
— income received, costs incurred — for a project. All tracked by the same
change_events triggers as everything else.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0018"
down_revision: str | None = "0017"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_NOW = "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')"
_TRACKED = (
    ("clients", "clients", "id"),
    ("projects", "projects", "id"),
    ("quote_revisions", "quote_revisions", "id"),
    ("project_links", "project_links", "id"),
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


def _enum(name: str, *values: str) -> sa.Enum:
    return sa.Enum(*values, name=name, native_enum=False, create_constraint=True, length=24)


def upgrade() -> None:
    op.create_table(
        "clients",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("name", sa.String(length=60), nullable=False),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("archived", sa.Boolean(), nullable=False, server_default=sa.text("0")),
        sa.Column("created_at", sa.String(length=32), nullable=False),
        sa.Column("updated_at", sa.String(length=32), nullable=False),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_clients")),
    )
    op.create_table(
        "projects",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column(
            "client_id",
            sa.String(length=36),
            sa.ForeignKey("clients.id", name="fk_projects_client_id_clients"),
            nullable=False,
        ),
        sa.Column("name", sa.String(length=80), nullable=False),
        sa.Column("kind", _enum("project_kind", "one_time", "monthly"), nullable=False),
        sa.Column("quote_paise", sa.Integer(), nullable=False),
        sa.Column("billing_day", sa.Integer(), nullable=True),
        sa.Column(
            "status",
            _enum("project_status", "quoted", "active", "done", "dropped"),
            nullable=False,
        ),
        sa.Column("started_at", sa.String(length=32), nullable=False),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("created_at", sa.String(length=32), nullable=False),
        sa.Column("updated_at", sa.String(length=32), nullable=False),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_projects")),
    )
    op.create_index(op.f("ix_projects_client_id"), "projects", ["client_id"], unique=False)
    op.create_table(
        "quote_revisions",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column(
            "project_id",
            sa.String(length=36),
            sa.ForeignKey("projects.id", name="fk_quote_revisions_project_id_projects"),
            nullable=False,
        ),
        sa.Column("paise", sa.Integer(), nullable=False),
        sa.Column("reason", sa.Text(), nullable=True),
        sa.Column("at", sa.String(length=32), nullable=False),
        sa.Column("created_at", sa.String(length=32), nullable=False),
        sa.Column("updated_at", sa.String(length=32), nullable=False),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_quote_revisions")),
    )
    op.create_index(
        op.f("ix_quote_revisions_project_id"), "quote_revisions", ["project_id"], unique=False
    )
    op.create_table(
        "project_links",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column(
            "project_id",
            sa.String(length=36),
            sa.ForeignKey("projects.id", name="fk_project_links_project_id_projects"),
            nullable=False,
        ),
        sa.Column(
            "txn_id",
            sa.String(length=36),
            sa.ForeignKey("txns.id", name="fk_project_links_txn_id_txns"),
            nullable=False,
        ),
        sa.Column("role", _enum("link_role", "received", "cost"), nullable=False),
        sa.Column("billable", sa.Boolean(), nullable=False, server_default=sa.text("0")),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("at", sa.String(length=32), nullable=False),
        sa.Column("created_at", sa.String(length=32), nullable=False),
        sa.Column("updated_at", sa.String(length=32), nullable=False),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_project_links")),
    )
    op.create_index(
        op.f("ix_project_links_project_id"), "project_links", ["project_id"], unique=False
    )
    op.create_index(op.f("ix_project_links_txn_id"), "project_links", ["txn_id"], unique=False)
    for table, resource, key in _TRACKED:
        _sync_triggers(table, resource, key)


def downgrade() -> None:
    for table, _, _ in _TRACKED:
        for suffix in ("insert", "update", "delete"):
            op.execute(f"DROP TRIGGER IF EXISTS trg_sync_{table}_{suffix}")
    op.drop_table("project_links")
    op.drop_table("quote_revisions")
    op.drop_table("projects")
    op.drop_table("clients")
