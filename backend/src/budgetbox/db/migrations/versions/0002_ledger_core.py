"""ledger core: accounts, anchors, categories (+seeds), txns, pinned, seals,
activities, settings

Revision ID: 0002
Revises: 0001

Custom column types (UTCInstant, DayKey, string enums) are written here as the
TEXT they actually are — migrations describe storage, models describe meaning.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0002"
down_revision: str | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

# Fixed seed timestamp/ids: migrations must be deterministic.
_SEED_AT = "2026-07-01T00:00:00.000000+00:00"
_SEED_CATEGORIES = [
    # (id, name, icon, kind, sort_order) — mirrors the app's db.dart seeds.
    ("019fb983-3f3c-7c0c-a3d1-5ca809294bdf", "Food & chai", "cup", "expense", 0),
    ("019fb983-3f3d-7628-af74-c9b2c624f57b", "Getting around", "bus", "expense", 1),
    ("019fb983-3f3e-7b3c-bee6-17ebf0c0323f", "Kirana & home", "basket", "expense", 2),
    ("019fb983-3f3f-7016-a6de-e0cbf1fe0c30", "Rent", "home", "expense", 3),
    ("019fb983-3f40-7b81-b03d-e309e10de82e", "Bills & recharge", "bill", "expense", 4),
    ("019fb983-3f41-757c-ade5-7dae195cb7fb", "Fun & extras", "film", "expense", 5),
    ("019fb983-3f42-7749-ab63-7cf7b2868853", "Health", "health", "expense", 6),
    ("019fb983-3f43-7434-bf92-31bebc150c34", "Family & gifts", "gift", "expense", 7),
    ("019fb983-3f44-7954-afad-51289be99bbc", "Salary", "work", "income", 0),
    ("019fb983-3f45-72d1-b466-4677a3649a3c", "Extra income", "up", "income", 1),
]


def upgrade() -> None:
    op.create_table(
        "accounts",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("name", sa.String(length=60), nullable=False),
        sa.Column(
            "kind",
            sa.Enum(
                "bank",
                "upi",
                "cash",
                "card",
                "asset",
                "liability",
                name="account_kind",
                native_enum=False,
                create_constraint=True,
                length=24,
            ),
            nullable=False,
        ),
        sa.Column("sort_order", sa.Integer(), nullable=False),
        sa.Column("archived", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.String(length=32), nullable=False),
        sa.Column("updated_at", sa.String(length=32), nullable=False),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_accounts")),
    )
    op.create_table(
        "activities",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("txn_id", sa.String(length=36), nullable=False),
        sa.Column(
            "action",
            sa.Enum(
                "created",
                "edited",
                "deleted",
                name="activity_action",
                native_enum=False,
                create_constraint=True,
                length=24,
            ),
            nullable=False,
        ),
        sa.Column("snapshot", sa.Text(), nullable=False),
        sa.Column("at", sa.String(length=32), nullable=False),
        sa.Column("created_at", sa.String(length=32), nullable=False),
        sa.Column("updated_at", sa.String(length=32), nullable=False),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_activities")),
    )
    op.create_table(
        "categories",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("name", sa.String(length=40), nullable=False),
        sa.Column("icon", sa.String(length=24), nullable=False),
        sa.Column(
            "kind",
            sa.Enum(
                "expense",
                "income",
                name="category_kind",
                native_enum=False,
                create_constraint=True,
                length=24,
            ),
            nullable=False,
        ),
        sa.Column("sort_order", sa.Integer(), nullable=False),
        sa.Column("archived", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.String(length=32), nullable=False),
        sa.Column("updated_at", sa.String(length=32), nullable=False),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_categories")),
    )
    op.create_table(
        "day_seals",
        sa.Column("date", sa.String(length=10), nullable=False),
        sa.Column("sealed_at", sa.String(length=32), nullable=False),
        sa.Column("created_at", sa.String(length=32), nullable=False),
        sa.Column("updated_at", sa.String(length=32), nullable=False),
        sa.PrimaryKeyConstraint("date", name=op.f("pk_day_seals")),
    )
    op.create_table(
        "settings",
        sa.Column("key", sa.String(length=40), nullable=False),
        sa.Column("value", sa.Text(), nullable=False),
        sa.Column("created_at", sa.String(length=32), nullable=False),
        sa.Column("updated_at", sa.String(length=32), nullable=False),
        sa.PrimaryKeyConstraint("key", name=op.f("pk_settings")),
    )
    op.create_table(
        "balance_anchors",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("account_id", sa.String(length=36), nullable=False),
        sa.Column("at", sa.String(length=32), nullable=False),
        sa.Column("balance_paise", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.String(length=32), nullable=False),
        sa.Column("updated_at", sa.String(length=32), nullable=False),
        sa.ForeignKeyConstraint(
            ["account_id"], ["accounts.id"], name=op.f("fk_balance_anchors_account_id_accounts")
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_balance_anchors")),
    )
    with op.batch_alter_table("balance_anchors", schema=None) as batch_op:
        batch_op.create_index("ix_balance_anchors_account_at", ["account_id", "at"], unique=False)

    op.create_table(
        "pinneds",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("title", sa.String(length=120), nullable=False),
        sa.Column("amount_paise", sa.Integer(), nullable=False),
        sa.Column("category_id", sa.String(length=36), nullable=False),
        sa.Column("account_id", sa.String(length=36), nullable=False),
        sa.Column("sort_order", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.String(length=32), nullable=False),
        sa.Column("updated_at", sa.String(length=32), nullable=False),
        sa.ForeignKeyConstraint(
            ["account_id"], ["accounts.id"], name=op.f("fk_pinneds_account_id_accounts")
        ),
        sa.ForeignKeyConstraint(
            ["category_id"], ["categories.id"], name=op.f("fk_pinneds_category_id_categories")
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_pinneds")),
    )
    op.create_table(
        "txns",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("amount_paise", sa.Integer(), nullable=False),
        sa.Column(
            "type",
            sa.Enum(
                "expense",
                "income",
                "transfer",
                name="txn_type",
                native_enum=False,
                create_constraint=True,
                length=24,
            ),
            nullable=False,
        ),
        sa.Column("category_id", sa.String(length=36), nullable=True),
        sa.Column("account_id", sa.String(length=36), nullable=False),
        sa.Column("to_account_id", sa.String(length=36), nullable=True),
        sa.Column("title", sa.String(length=120), nullable=False),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("at", sa.String(length=32), nullable=False),
        sa.Column("goal_id", sa.String(length=36), nullable=True),
        sa.Column("recurring_id", sa.String(length=36), nullable=True),
        sa.Column("created_at", sa.String(length=32), nullable=False),
        sa.Column("updated_at", sa.String(length=32), nullable=False),
        sa.CheckConstraint(
            "(type = 'transfer') = (to_account_id IS NOT NULL)",
            name=op.f("ck_txns_transfer_shape"),
        ),
        sa.CheckConstraint(
            "type != 'transfer' OR category_id IS NULL",
            name=op.f("ck_txns_transfer_has_no_category"),
        ),
        sa.CheckConstraint("amount_paise > 0", name=op.f("ck_txns_amount_positive")),
        sa.ForeignKeyConstraint(
            ["account_id"], ["accounts.id"], name=op.f("fk_txns_account_id_accounts")
        ),
        sa.ForeignKeyConstraint(
            ["category_id"], ["categories.id"], name=op.f("fk_txns_category_id_categories")
        ),
        sa.ForeignKeyConstraint(
            ["to_account_id"], ["accounts.id"], name=op.f("fk_txns_to_account_id_accounts")
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_txns")),
    )
    with op.batch_alter_table("txns", schema=None) as batch_op:
        batch_op.create_index("ix_txns_at_id", ["at", "id"], unique=False)

    categories = sa.table(
        "categories",
        sa.column("id", sa.String),
        sa.column("name", sa.String),
        sa.column("icon", sa.String),
        sa.column("kind", sa.String),
        sa.column("sort_order", sa.Integer),
        sa.column("archived", sa.Boolean),
        sa.column("created_at", sa.String),
        sa.column("updated_at", sa.String),
    )
    op.bulk_insert(
        categories,
        [
            {
                "id": cid,
                "name": name,
                "icon": icon,
                "kind": kind,
                "sort_order": order,
                "archived": False,
                "created_at": _SEED_AT,
                "updated_at": _SEED_AT,
            }
            for cid, name, icon, kind, order in _SEED_CATEGORIES
        ],
    )


def downgrade() -> None:
    with op.batch_alter_table("txns", schema=None) as batch_op:
        batch_op.drop_index("ix_txns_at_id")
    op.drop_table("txns")
    op.drop_table("pinneds")
    with op.batch_alter_table("balance_anchors", schema=None) as batch_op:
        batch_op.drop_index("ix_balance_anchors_account_at")
    op.drop_table("balance_anchors")
    op.drop_table("settings")
    op.drop_table("day_seals")
    op.drop_table("categories")
    op.drop_table("activities")
    op.drop_table("accounts")
