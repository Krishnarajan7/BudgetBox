"""The music book: aggregates, the IST month boundary, the importer's three
refusals (too short, not music, past the poll cutoff), and the callback guard."""

import datetime as dt
import json
from pathlib import Path

import pytest
from sqlalchemy.orm import Session

from budgetbox.core.ids import new_id
from budgetbox.modules.music import service
from budgetbox.modules.music.importer import import_directory
from budgetbox.modules.music.models import (
    MusicArtist,
    MusicPlay,
    MusicTrack,
    PlaySource,
    SpotifyLink,
)

UTC = dt.UTC


def _artist(session: Session, name: str) -> MusicArtist:
    row = MusicArtist(id=new_id(), name=name)
    session.add(row)
    session.flush()
    return row


def _track(session: Session, name: str, artist: MusicArtist, duration: int = 200_000) -> MusicTrack:
    row = MusicTrack(id=new_id(), name=name, artist_id=artist.id, duration_ms=duration)
    session.add(row)
    session.flush()
    return row


def _play(
    session: Session,
    track: MusicTrack,
    at: dt.datetime,
    ms: int = 200_000,
    source: PlaySource = PlaySource.IMPORT,
) -> None:
    session.add(
        MusicPlay(id=new_id(), played_at=at, track_id=track.id, ms_played=ms, source=source)
    )


def test_overview_counts_and_since(session: Session) -> None:
    a = _artist(session, "Ilaiyaraaja")
    t1 = _track(session, "Thendral Vanthu", a)
    t2 = _track(session, "Rakkamma", a)
    _play(session, t1, dt.datetime(2024, 3, 1, 10, 0, tzinfo=UTC))
    _play(session, t1, dt.datetime(2024, 3, 2, 10, 0, tzinfo=UTC))
    _play(session, t2, dt.datetime(2024, 3, 3, 10, 0, tzinfo=UTC), source=PlaySource.POLL)
    session.commit()

    out = service.overview(session)
    assert out.total_plays == 3
    assert out.total_ms == 600_000
    assert out.distinct_tracks == 2
    assert out.distinct_artists == 1
    assert out.since == dt.datetime(2024, 3, 1, 10, 0, tzinfo=UTC)
    # recording_since is the first *polled* play, not the first imported one.
    assert out.recording_since == dt.datetime(2024, 3, 3, 10, 0, tzinfo=UTC)
    assert out.connected is False


def test_top_tracks_ranked_by_plays(session: Session) -> None:
    a = _artist(session, "A. R. Rahman")
    hit = _track(session, "Kadhal Rojave", a)
    other = _track(session, "Uyire", a)
    for day in range(3):
        _play(session, hit, dt.datetime(2024, 5, 1 + day, 9, 0, tzinfo=UTC))
    _play(session, other, dt.datetime(2024, 5, 1, 12, 0, tzinfo=UTC))
    session.commit()

    top = service.top(session, kind="tracks", range_key="all", limit=10)
    assert [e.name for e in top] == ["Kadhal Rojave", "Uyire"]
    assert top[0].rank == 1 and top[0].plays == 3
    assert top[0].artist == "A. R. Rahman"

    artists = service.top(session, kind="artists", range_key="all", limit=10)
    assert artists[0].name == "A. R. Rahman" and artists[0].plays == 4


def test_month_bucketing_follows_ist(session: Session) -> None:
    """19:00 UTC on 31 July is 00:30 IST on 1 August — an August play."""
    a = _artist(session, "Anirudh")
    t = _track(session, "Chuttamalle", a)
    _play(session, t, dt.datetime(2024, 7, 31, 19, 0, tzinfo=UTC))
    _play(session, t, dt.datetime(2024, 7, 31, 10, 0, tzinfo=UTC))
    session.commit()

    months = service.months(session)
    assert [(m.month, m.plays) for m in months] == [("2024-08", 1), ("2024-07", 1)]
    assert months[0].top_track is not None
    assert months[0].top_track.name == "Chuttamalle"

    detail = service.month_detail(session, dt.date(2024, 8, 1))
    assert detail.plays == 1
    assert detail.tracks[0].name == "Chuttamalle"


def test_top_range_validation(session: Session) -> None:
    from budgetbox.core.errors import Invalid

    with pytest.raises(Invalid):
        service.top(session, kind="tracks", range_key="week", limit=5)
    with pytest.raises(Invalid):
        service.top(session, kind="albums", range_key="all", limit=5)


def _export_entry(
    ts: str,
    track: str | None = "Vaathi Coming",
    artist: str | None = "Anirudh",
    ms: int = 180_000,
) -> dict[str, object]:
    return {
        "ts": ts,
        "ms_played": ms,
        "master_metadata_track_name": track,
        "master_metadata_album_artist_name": artist,
        "master_metadata_album_album_name": "Master",
        "spotify_track_uri": "spotify:track:abc123",
    }


def test_import_rules(session: Session, tmp_path: Path) -> None:
    # A polled play establishes the cutoff: nothing at/after it is imported.
    a = _artist(session, "Anirudh")
    t = _track(session, "Vaathi Coming", a)
    cutoff = dt.datetime(2026, 1, 1, 0, 0, tzinfo=UTC)
    _play(session, t, cutoff, source=PlaySource.POLL)
    session.commit()

    entries = [
        _export_entry("2025-06-01T10:00:00Z"),  # counts
        _export_entry("2025-06-01T11:00:00Z", ms=5_000),  # too short: skipped
        _export_entry("2025-06-01T12:00:00Z", track=None, artist=None),  # a podcast
        _export_entry("2026-01-02T10:00:00Z"),  # past the poll cutoff
        _export_entry("2025-06-01T10:00:00Z"),  # duplicate timestamp
    ]
    (tmp_path / "Streaming_History_Audio_2025_0.json").write_text(json.dumps(entries))

    summary = import_directory(session, tmp_path)
    assert "imported 1 play(s)" in summary

    plays = session.query(MusicPlay).filter(MusicPlay.source == PlaySource.IMPORT).all()
    assert len(plays) == 1
    assert plays[0].ms_played == 180_000
    # The import found the existing track through its name and artist.
    assert plays[0].track_id == t.id
    # Re-running adds nothing: played_at is the natural key.
    assert "imported 0 play(s)" in import_directory(session, tmp_path)


def test_import_refuses_empty_directory(session: Session, tmp_path: Path) -> None:
    from budgetbox.core.errors import Invalid

    with pytest.raises(Invalid):
        import_directory(session, tmp_path)


def test_overview_over_api(client) -> None:  # type: ignore[no-untyped-def]
    body = client.get("/v1/music/overview").json()
    assert body["connected"] is False
    assert body["total_plays"] == 0
    assert body["since"] is None


def test_callback_refuses_wrong_state(anon_client, session: Session) -> None:  # type: ignore[no-untyped-def]
    # A handshake is open…
    link = SpotifyLink(id="spotify", auth_state="right-state", code_verifier="v" * 43)
    session.merge(link)
    session.commit()
    # …but the callback arrives with someone else's state: refused, code unspent.
    response = anon_client.get("/spotify/callback", params={"code": "x", "state": "wrong"})
    assert response.status_code == 400
    assert "start the connection again" in response.text.lower()


def test_callback_without_open_handshake(anon_client) -> None:  # type: ignore[no-untyped-def]
    response = anon_client.get("/spotify/callback", params={"code": "x", "state": "s"})
    assert response.status_code == 400
