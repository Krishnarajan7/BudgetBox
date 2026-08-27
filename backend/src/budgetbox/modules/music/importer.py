"""The one-time backfill: Spotify's GDPR 'extended streaming history' export
(Privacy Settings → Download your data), a directory of
Streaming_History_Audio_*.json files reaching back to the account's first day.

Rules of the import:
- Spotify's own bar applies: under 30 seconds listened is not a play.
- Podcast entries (episode fields, no track name) are not music.
- Nothing at or past the first *polled* play is taken — the poll's record is
  authoritative there, and the export's timestamps differ by a few seconds,
  which would double-count every overlapping play.
"""

import datetime as dt
import json
from pathlib import Path
from typing import cast

import structlog
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from budgetbox.core.errors import Invalid
from budgetbox.core.ids import new_id
from budgetbox.modules.music.models import MusicArtist, MusicPlay, MusicTrack, PlaySource
from budgetbox.modules.music.service import artist_for, track_for
from budgetbox.modules.music.spotify import jint, jstr

log = structlog.get_logger()

_MIN_LISTENED_MS = 30_000


def import_directory(session: Session, directory: Path) -> str:
    """Idempotent: `played_at` is unique, so re-running an import only adds
    what a previous run missed."""
    files = sorted(directory.glob("Streaming_History_Audio*.json"))
    if not files:
        raise Invalid(f"No Streaming_History_Audio*.json files in {directory}")

    cutoff = session.scalar(
        select(func.min(MusicPlay.played_at)).where(MusicPlay.source == PlaySource.POLL)
    )
    artists: dict[str, MusicArtist] = {}
    tracks: dict[str, MusicTrack] = {}
    seen = set(session.scalars(select(MusicPlay.played_at)))

    total_created = 0
    total_skipped = 0
    for file in files:
        entries: object = json.loads(file.read_text())
        if not isinstance(entries, list):
            raise Invalid(f"{file.name} is not a JSON array")
        created = 0
        for entry in cast(list[object], entries):
            track_name = jstr(entry, "master_metadata_track_name")
            artist_name = jstr(entry, "master_metadata_album_artist_name")
            ts = jstr(entry, "ts")
            ms_played = jint(entry, "ms_played")
            if track_name is None or artist_name is None:
                total_skipped += 1  # podcasts, audiobooks, deleted tracks
                continue
            if ts is None or ms_played is None:
                total_skipped += 1
                continue
            if ms_played < _MIN_LISTENED_MS:
                total_skipped += 1
                continue
            played_at = dt.datetime.fromisoformat(ts.replace("Z", "+00:00"))
            if cutoff is not None and played_at >= cutoff:
                total_skipped += 1
                continue
            if played_at in seen:
                continue
            seen.add(played_at)

            uri = jstr(entry, "spotify_track_uri")
            spotify_id = (
                uri.removeprefix("spotify:track:")
                if uri is not None and uri.startswith("spotify:track:")
                else None
            )
            artist = artist_for(session, artist_name, None, artists)
            track = track_for(
                session,
                track_name,
                artist,
                spotify_id,
                jstr(entry, "master_metadata_album_album_name"),
                None,
                None,
                tracks,
            )
            session.add(
                MusicPlay(
                    id=new_id(),
                    played_at=played_at,
                    track_id=track.id,
                    ms_played=ms_played,
                    source=PlaySource.IMPORT,
                )
            )
            created += 1
        session.commit()
        total_created += created
        log.info("music_import_file", file=file.name, created=created)

    return f"imported {total_created} play(s) from {len(files)} file(s), skipped {total_skipped}"
