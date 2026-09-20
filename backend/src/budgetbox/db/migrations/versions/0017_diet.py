"""the diet book — what was eaten, weighed on the phone

Revision ID: 0017
Revises: 0016

Meals arrive with their nutrients already worked out (`facts`), because the
food table lives on the phone and the server has no business owning a copy
that could drift from it. Tracked by the same change_events triggers as
everything else, so a reinstall pulls the plate down whole.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0017"
down_revision: str | None = "0016"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_NOW = "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')"
_TRACKED = (("meals", "meals", "id"),)


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
        "meals",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("date", sa.String(length=10), nullable=False),
        sa.Column(
            "slot",
            sa.Enum(
                "breakfast",
                "lunch",
                "snack",
                "dinner",
                name="meal_slot",
                native_enum=False,
                create_constraint=True,
                length=24,
            ),
            nullable=False,
        ),
        sa.Column("food_key", sa.String(length=24), nullable=True),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column("servings", sa.Float(), nullable=False, server_default=sa.text("1.0")),
        sa.Column("grams", sa.Float(), nullable=True),
        sa.Column("facts", sa.Text(), nullable=True),
        sa.Column("skipped", sa.Boolean(), nullable=False, server_default=sa.text("0")),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("at", sa.String(length=32), nullable=False),
        sa.Column("created_at", sa.String(length=32), nullable=False),
        sa.Column("updated_at", sa.String(length=32), nullable=False),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_meals")),
    )
    op.create_index(op.f("ix_meals_date"), "meals", ["date"], unique=False)
    for table, resource, key in _TRACKED:
        _sync_triggers(table, resource, key)


def downgrade() -> None:
    for table, _, _ in _TRACKED:
        for suffix in ("insert", "update", "delete"):
            op.execute(f"DROP TRIGGER IF EXISTS trg_sync_{table}_{suffix}")
    op.drop_index(op.f("ix_meals_date"), table_name="meals")
    op.drop_table("meals")
