"""The record of listening. Spotify's API only ever shows the last 50 plays —
a rolling window, not a history — so this module's job is to keep what Spotify
forgets: every play, polled every half hour, plus the one-time GDPR import
that reaches back to the account's first day."""

import datetime as dt
import enum

from sqlalchemy import CheckConstraint, ForeignKey, Index, String
from sqlalchemy.orm import Mapped, mapped_column

from budgetbox.db.base import Base, StampedMixin, UTCInstant, pk_id, str_enum


class PlaySource(enum.StrEnum):
    """Where a play was learned from: the half-hour poll, or the GDPR export."""

    POLL = "poll"
    IMPORT = "import"


class SpotifyLink(Base, StampedMixin):
    """The single connection to Spotify — one user, one row (id='spotify').
    Also the parking spot for an in-flight PKCE handshake: state and verifier
    live here between /music/spotify/connect and the browser's callback."""

    __tablename__ = "spotify_link"

    id: Mapped[str] = pk_id()
    refresh_token: Mapped[str | None] = mapped_column(String(300), default=None)
    access_token: Mapped[str | None] = mapped_column(String(400), default=None)
    access_expires_at: Mapped[dt.datetime | None] = mapped_column(UTCInstant(), default=None)
    auth_state: Mapped[str | None] = mapped_column(String(64), default=None)
    code_verifier: Mapped[str | None] = mapped_column(String(128), default=None)
    connected_at: Mapped[dt.datetime | None] = mapped_column(UTCInstant(), default=None)


class MusicArtist(Base, StampedMixin):
    """Dimension row. The GDPR export knows artists only by name; the poll
    knows their Spotify id and can fetch a portrait — the two meet on name."""

    __tablename__ = "music_artists"
    __table_args__ = (Index("ix_music_artists_name", "name"),)

    id: Mapped[str] = pk_id()
    spotify_id: Mapped[str | None] = mapped_column(String(32), unique=True, default=None)
    name: Mapped[str] = mapped_column(String(200))
    image_url: Mapped[str | None] = mapped_column(String(300), default=None)


class MusicTrack(Base, StampedMixin):
    """Dimension row, so a track renamed upstream never rewrites history."""

    __tablename__ = "music_tracks"
    __table_args__ = (Index("ix_music_tracks_artist_id", "artist_id"),)

    id: Mapped[str] = pk_id()
    spotify_id: Mapped[str | None] = mapped_column(String(32), unique=True, default=None)
    name: Mapped[str] = mapped_column(String(300))
    artist_id: Mapped[str] = mapped_column(String(36), ForeignKey("music_artists.id"))
    album: Mapped[str | None] = mapped_column(String(300), default=None)
    image_url: Mapped[str | None] = mapped_column(String(300), default=None)
    duration_ms: Mapped[int | None] = mapped_column(default=None)


class MusicPlay(Base):
    """One listened play (Spotify's own bar: 30 seconds or it didn't happen).
    `played_at` is unique — it is the natural dedup key between poll runs.
    No StampedMixin: plays are written once, never edited, never synced
    through /v1/changes, and an eight-year import is bulk enough that two
    spare timestamp columns per row would be pure ballast."""

    __tablename__ = "music_plays"
    __table_args__ = (
        CheckConstraint("ms_played >= 0", name="ms_played_not_negative"),
        Index("ix_music_plays_track_id", "track_id"),
    )

    id: Mapped[str] = pk_id()
    played_at: Mapped[dt.datetime] = mapped_column(UTCInstant(), unique=True)
    track_id: Mapped[str] = mapped_column(String(36), ForeignKey("music_tracks.id"))
    ms_played: Mapped[int]
    source: Mapped[PlaySource] = mapped_column(str_enum(PlaySource, "play_source"))
