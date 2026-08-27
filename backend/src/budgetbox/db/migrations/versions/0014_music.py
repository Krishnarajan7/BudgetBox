"""the music book — what Spotify forgets, kept

Revision ID: 0014
Revises: 0013

Spotify's API shows only the last 50 plays, ever. These four tables are the
memory it refuses to keep: the single account link (PKCE handshake and
tokens), artist and track dimension rows, and one row per listened play.
No change_events triggers: this book is server-native — the phone reads it
over /v1/music, nothing syncs down into Drift.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0014"
down_revision: str | None = "0013"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "spotify_link",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("refresh_token", sa.String(300), nullable=True),
        sa.Column("access_token", sa.String(400), nullable=True),
        sa.Column("access_expires_at", sa.String(32), nullable=True),
        sa.Column("auth_state", sa.String(64), nullable=True),
        sa.Column("code_verifier", sa.String(128), nullable=True),
        sa.Column("connected_at", sa.String(32), nullable=True),
        sa.Column("created_at", sa.String(32), nullable=False),
        sa.Column("updated_at", sa.String(32), nullable=False),
    )
    op.create_table(
        "music_artists",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("spotify_id", sa.String(32), nullable=True, unique=True),
        sa.Column("name", sa.String(200), nullable=False),
        sa.Column("image_url", sa.String(300), nullable=True),
        sa.Column("created_at", sa.String(32), nullable=False),
        sa.Column("updated_at", sa.String(32), nullable=False),
    )
    op.create_index("ix_music_artists_name", "music_artists", ["name"])
    op.create_table(
        "music_tracks",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("spotify_id", sa.String(32), nullable=True, unique=True),
        sa.Column("name", sa.String(300), nullable=False),
        sa.Column(
            "artist_id",
            sa.String(36),
            sa.ForeignKey("music_artists.id", name="fk_music_tracks_artist_id_music_artists"),
            nullable=False,
        ),
        sa.Column("album", sa.String(300), nullable=True),
        sa.Column("image_url", sa.String(300), nullable=True),
        sa.Column("duration_ms", sa.Integer, nullable=True),
        sa.Column("created_at", sa.String(32), nullable=False),
        sa.Column("updated_at", sa.String(32), nullable=False),
    )
    op.create_index("ix_music_tracks_artist_id", "music_tracks", ["artist_id"])
    op.create_table(
        "music_plays",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("played_at", sa.String(32), nullable=False, unique=True),
        sa.Column(
            "track_id",
            sa.String(36),
            sa.ForeignKey("music_tracks.id", name="fk_music_plays_track_id_music_tracks"),
            nullable=False,
        ),
        sa.Column("ms_played", sa.Integer, nullable=False),
        sa.Column(
            "source",
            sa.Enum(
                "poll",
                "import",
                name="play_source",
                native_enum=False,
                create_constraint=True,
                length=24,
            ),
            nullable=False,
        ),
        sa.CheckConstraint("ms_played >= 0", name="ck_music_plays_ms_played_not_negative"),
    )
    op.create_index("ix_music_plays_track_id", "music_plays", ["track_id"])


def downgrade() -> None:
    op.drop_table("music_plays")
    op.drop_table("music_tracks")
    op.drop_table("music_artists")
    op.drop_table("spotify_link")
