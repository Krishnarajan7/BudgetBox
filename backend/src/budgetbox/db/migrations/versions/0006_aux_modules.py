"""aux modules: notes, focus_sessions, journal_entries, events, vault_items

Revision ID: 0006
Revises: 0005
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0006"
down_revision: str | None = "0005"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "notes",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("body", sa.Text(), nullable=False),
        sa.Column("pinned", sa.Boolean(), nullable=False),
        sa.Column("archived", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.String(length=32), nullable=False),
        sa.Column("updated_at", sa.String(length=32), nullable=False),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_notes")),
    )
    op.create_table(
        "focus_sessions",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("started_at", sa.String(length=32), nullable=False),
        sa.Column("minutes", sa.Integer(), nullable=False),
        sa.Column(
            "kind",
            sa.Enum(
                "work",
                "rest",
                name="focus_kind",
                native_enum=False,
                create_constraint=True,
                length=24,
            ),
            nullable=False,
        ),
        sa.Column("completed", sa.Boolean(), nullable=False),
        sa.Column("label", sa.String(length=60), nullable=True),
        sa.Column("created_at", sa.String(length=32), nullable=False),
        sa.Column("updated_at", sa.String(length=32), nullable=False),
        sa.CheckConstraint("minutes > 0", name=op.f("ck_focus_sessions_minutes_positive")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_focus_sessions")),
    )
    op.create_table(
        "journal_entries",
        sa.Column("date", sa.String(length=10), nullable=False),
        sa.Column("body", sa.Text(), nullable=False),
        sa.Column("mood", sa.Integer(), nullable=True),
        sa.Column("created_at", sa.String(length=32), nullable=False),
        sa.Column("updated_at", sa.String(length=32), nullable=False),
        sa.CheckConstraint(
            "mood IS NULL OR mood BETWEEN 1 AND 5", name=op.f("ck_journal_entries_mood_range")
        ),
        sa.PrimaryKeyConstraint("date", name=op.f("pk_journal_entries")),
    )
    op.create_table(
        "events",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("title", sa.String(length=120), nullable=False),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("date", sa.String(length=10), nullable=False),
        sa.Column("time_minutes", sa.Integer(), nullable=True),
        sa.Column(
            "repeat",
            sa.Enum(
                "none",
                "yearly",
                name="event_repeat",
                native_enum=False,
                create_constraint=True,
                length=24,
            ),
            nullable=False,
        ),
        sa.Column("archived", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.String(length=32), nullable=False),
        sa.Column("updated_at", sa.String(length=32), nullable=False),
        sa.CheckConstraint(
            "time_minutes IS NULL OR time_minutes BETWEEN 0 AND 1439",
            name=op.f("ck_events_time_minutes_range"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_events")),
    )
    op.create_table(
        "vault_items",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("nonce", sa.Text(), nullable=False),
        sa.Column("cipher", sa.Text(), nullable=False),
        sa.Column("created_at", sa.String(length=32), nullable=False),
        sa.Column("updated_at", sa.String(length=32), nullable=False),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_vault_items")),
    )


def downgrade() -> None:
    op.drop_table("vault_items")
    op.drop_table("events")
    op.drop_table("journal_entries")
    op.drop_table("focus_sessions")
    op.drop_table("notes")
