"""Everything the music book knows how to do: hold the Spotify handshake,
poll the rolling 50-play window before it rolls away, and answer the four
questions the screen asks — how much, what most, who most, and month by month.

All bucketing is IST: a track heard at 00:30 belongs to that Indian day and
month, wherever the server runs. IST has no DST, so the +330-minute shift is
safe to do in SQL."""

import datetime as dt
from dataclasses import dataclass
from typing import Any

import structlog
from sqlalchemy import Select, func, select
from sqlalchemy.orm import Session

from budgetbox.core.config import Settings
from budgetbox.core.errors import Conflict, Invalid
from budgetbox.core.ids import new_id
from budgetbox.core.time import ist_day_start, now_utc, today_ist
from budgetbox.modules.music import spotify
from budgetbox.modules.music.models import (
    MusicArtist,
    MusicPlay,
    MusicTrack,
    PlaySource,
    SpotifyLink,
)
from budgetbox.modules.music.schemas import (
    ConnectOut,
    MonthDetailOut,
    MonthOut,
    MonthTopOut,
    NowOut,
    OverviewOut,
    TopEntryOut,
)

log = structlog.get_logger()

_LINK_ID = "spotify"

# A handshake left half-open is abandoned after ten minutes.
_HANDSHAKE_TTL = dt.timedelta(minutes=10)

# The month key in IST, computed where the plays live.
_IST_MONTH = func.strftime("%Y-%m", func.datetime(MusicPlay.played_at, "+330 minutes"))


# ————— the link —————


def get_link(session: Session) -> SpotifyLink:
    link = session.get(SpotifyLink, _LINK_ID)
    if link is None:
        link = SpotifyLink(id=_LINK_ID)
        session.add(link)
        session.flush()
    return link


def _client_id(cfg: Settings) -> str:
    if not cfg.spotify_client_id:
        raise Invalid("BBX_SPOTIFY_CLIENT_ID is not configured on the server.")
    return cfg.spotify_client_id


def connect_begin(session: Session, cfg: Settings) -> ConnectOut:
    """Mint a PKCE handshake and hand back the consent URL. Idempotent in
    spirit: a new call simply replaces any half-open handshake."""
    if not cfg.spotify_redirect_uri:
        raise Invalid("BBX_SPOTIFY_REDIRECT_URI is not configured on the server.")
    state, verifier, challenge = spotify.make_pkce()
    link = get_link(session)
    link.auth_state = state
    link.code_verifier = verifier
    link.updated_at = now_utc()
    session.commit()
    return ConnectOut(
        url=spotify.authorize_url(_client_id(cfg), cfg.spotify_redirect_uri, state, challenge)
    )


def connect_finish(session: Session, cfg: Settings, code: str, state: str) -> None:
    """The browser came back. The state must match the open handshake and the
    handshake must be fresh — otherwise the code is refused unspent."""
    link = get_link(session)
    if not link.auth_state or not link.code_verifier:
        raise Conflict("No Spotify connection attempt is open.")
    if state != link.auth_state:
        raise Conflict("State mismatch — start the connection again.")
    if now_utc() - link.updated_at > _HANDSHAKE_TTL:
        raise Conflict("The connection attempt expired — start again.")
    tokens = spotify.exchange_code(
        _client_id(cfg), cfg.spotify_redirect_uri, code, link.code_verifier
    )
    if tokens.refresh_token is None:
        raise Conflict("Spotify returned no refresh token; try connecting again.")
    link.refresh_token = tokens.refresh_token
    link.access_token = tokens.access_token
    link.access_expires_at = tokens.expires_at
    link.auth_state = None
    link.code_verifier = None
    link.connected_at = now_utc()
    session.commit()
    log.info("spotify_connected")


def _access_token(session: Session, cfg: Settings) -> str | None:
    """A live access token, refreshed when within a minute of dying.
    None when Spotify was never connected."""
    link = get_link(session)
    if not link.refresh_token:
        return None
    fresh_until = now_utc() + dt.timedelta(seconds=60)
    if link.access_token and link.access_expires_at and link.access_expires_at > fresh_until:
        return link.access_token
    tokens = spotify.refresh_tokens(_client_id(cfg), link.refresh_token)
    link.access_token = tokens.access_token
    link.access_expires_at = tokens.expires_at
    # Spotify may rotate the refresh token; keep whichever is newest.
    if tokens.refresh_token:
        link.refresh_token = tokens.refresh_token
    session.commit()
    return tokens.access_token


# ————— writing plays —————


def artist_for(
    session: Session, name: str, spotify_id: str | None, cache: dict[str, MusicArtist]
) -> MusicArtist:
    """By Spotify id first, then by name (the GDPR export only knows names).
    A polled play may thus adopt an imported artist and teach it its id."""
    key = spotify_id or f"name:{name}"
    if key in cache:
        return cache[key]
    row: MusicArtist | None = None
    if spotify_id is not None:
        row = session.scalar(select(MusicArtist).where(MusicArtist.spotify_id == spotify_id))
    if row is None:
        row = session.scalar(
            select(MusicArtist).where(MusicArtist.name == name, MusicArtist.spotify_id.is_(None))
        )
        if row is not None and spotify_id is not None:
            row.spotify_id = spotify_id
    if row is None:
        row = MusicArtist(id=new_id(), spotify_id=spotify_id, name=name)
        session.add(row)
        session.flush()
    cache[key] = row
    return row


def track_for(
    session: Session,
    name: str,
    artist: MusicArtist,
    spotify_id: str | None,
    album: str | None,
    image_url: str | None,
    duration_ms: int | None,
    cache: dict[str, MusicTrack],
) -> MusicTrack:
    key = spotify_id or f"name:{artist.id}:{name}"
    if key in cache:
        return cache[key]
    row: MusicTrack | None = None
    if spotify_id is not None:
        row = session.scalar(select(MusicTrack).where(MusicTrack.spotify_id == spotify_id))
    if row is None:
        row = session.scalar(
            select(MusicTrack).where(
                MusicTrack.name == name,
                MusicTrack.artist_id == artist.id,
                MusicTrack.spotify_id.is_(None),
            )
        )
        if row is not None and spotify_id is not None:
            row.spotify_id = spotify_id
    if row is None:
        row = MusicTrack(
            id=new_id(),
            spotify_id=spotify_id,
            name=name,
            artist_id=artist.id,
            album=album,
            image_url=image_url,
            duration_ms=duration_ms,
        )
        session.add(row)
        session.flush()
    else:
        # The poll knows more than the import did; let richer data land.
        if image_url and not row.image_url:
            row.image_url = image_url
        if duration_ms and not row.duration_ms:
            row.duration_ms = duration_ms
        if album and not row.album:
            row.album = album
    cache[key] = row
    return row


def _known_played_ats(session: Session, instants: list[dt.datetime]) -> set[dt.datetime]:
    if not instants:
        return set()
    rows = session.scalars(select(MusicPlay.played_at).where(MusicPlay.played_at.in_(instants)))
    return set(rows)


def poll(session: Session, cfg: Settings) -> str:
    """The half-hour heartbeat: everything newer than the last polled play.
    Not connected is a quiet no-op, not a failure — the job stays green
    while the book simply hasn't been opened to Spotify yet."""
    token = _access_token(session, cfg)
    if token is None:
        return "spotify not connected"

    last = session.scalar(
        select(func.max(MusicPlay.played_at)).where(MusicPlay.source == PlaySource.POLL)
    )
    after_ms = None if last is None else int(last.timestamp() * 1000)
    items = spotify.recently_played(token, after_ms)

    artists: dict[str, MusicArtist] = {}
    tracks: dict[str, MusicTrack] = {}
    parsed: list[tuple[dt.datetime, object]] = []
    for item in items:
        played_raw = spotify.jstr(item, "played_at")
        track = spotify.jget(item, "track")
        if played_raw is None or track is None:
            continue
        played_at = dt.datetime.fromisoformat(played_raw.replace("Z", "+00:00"))
        parsed.append((played_at, track))

    seen = _known_played_ats(session, [at for at, _ in parsed])
    created = 0
    for played_at, track in parsed:
        if played_at in seen:
            continue
        seen.add(played_at)
        track_artists = spotify.jlist(track, "artists")
        first_artist = track_artists[0] if track_artists else None
        album = spotify.jget(track, "album")
        images = spotify.jlist(album, "images")
        artist = artist_for(
            session,
            spotify.jstr(first_artist, "name") or "Unknown artist",
            spotify.jstr(first_artist, "id"),
            artists,
        )
        row = track_for(
            session,
            spotify.jstr(track, "name") or "Unknown track",
            artist,
            spotify.jstr(track, "id"),
            spotify.jstr(album, "name"),
            spotify.jstr(images[0], "url") if images else None,
            spotify.jint(track, "duration_ms"),
            tracks,
        )
        session.add(
            MusicPlay(
                id=new_id(),
                played_at=played_at,
                track_id=row.id,
                # The poll doesn't know true listened time; the track length
                # is the honest estimate for a play that counted at all.
                ms_played=row.duration_ms or 0,
                source=PlaySource.POLL,
            )
        )
        created += 1

    enriched = _enrich_artist_images(session, token, limit=5)
    session.commit()
    return f"recorded {created} play(s), {enriched} portrait(s)"


def _enrich_artist_images(session: Session, token: str, limit: int) -> int:
    """A few portraits per poll for artists that still lack one, most-played
    first — the wall fills in over a handful of heartbeats, without ever
    hammering the API in one go."""
    rows = session.scalars(
        select(MusicArtist)
        .join(MusicTrack, MusicTrack.artist_id == MusicArtist.id)
        .join(MusicPlay, MusicPlay.track_id == MusicTrack.id)
        .where(MusicArtist.image_url.is_(None), MusicArtist.spotify_id.is_not(None))
        .group_by(MusicArtist.id)
        .order_by(func.count().desc())
        .limit(limit)
    ).all()
    done = 0
    for artist in rows:
        assert artist.spotify_id is not None
        try:
            url = spotify.artist_image(token, artist.spotify_id)
        except spotify.SpotifyError:
            break  # rate limited or unwell; next poll will try again
        if url:
            artist.image_url = url
            done += 1
    return done


# ————— reading —————


def _range_start(range_key: str) -> dt.datetime | None:
    today = today_ist()
    if range_key == "month":
        return ist_day_start(today.replace(day=1))
    if range_key == "year":
        return ist_day_start(today.replace(month=1, day=1))
    if range_key == "all":
        return None
    raise Invalid("range must be one of: month, year, all")


def overview(session: Session) -> OverviewOut:
    link = session.get(SpotifyLink, _LINK_ID)
    connected = bool(link and link.refresh_token)
    total_plays, total_ms = _plays_and_ms(session, select(MusicPlay))
    month_plays, month_ms = _plays_and_ms(
        session,
        select(MusicPlay).where(MusicPlay.played_at >= ist_day_start(today_ist().replace(day=1))),
    )
    return OverviewOut(
        connected=connected,
        since=session.scalar(select(func.min(MusicPlay.played_at))),
        recording_since=session.scalar(
            select(func.min(MusicPlay.played_at)).where(MusicPlay.source == PlaySource.POLL)
        ),
        total_plays=total_plays,
        total_ms=total_ms,
        distinct_tracks=session.scalar(select(func.count(func.distinct(MusicPlay.track_id)))) or 0,
        distinct_artists=session.scalar(
            select(func.count(func.distinct(MusicTrack.artist_id))).join_from(
                MusicPlay, MusicTrack, MusicPlay.track_id == MusicTrack.id
            )
        )
        or 0,
        this_month_plays=month_plays,
        this_month_ms=month_ms,
    )


def _plays_and_ms(session: Session, base: Select[Any]) -> tuple[int, int]:
    sub = base.subquery()
    row = session.execute(
        select(func.count(), func.coalesce(func.sum(sub.c.ms_played), 0)).select_from(sub)
    ).one()
    return int(row[0]), int(row[1])


@dataclass(frozen=True)
class _Window:
    start: dt.datetime | None = None
    month: str | None = None

    def apply(self, stmt: Select[Any]) -> Select[Any]:
        if self.start is not None:
            stmt = stmt.where(MusicPlay.played_at >= self.start)
        if self.month is not None:
            stmt = stmt.where(_IST_MONTH == self.month)  # noqa: SIM300 — SQL, not a comparison
        return stmt


def _top_tracks(session: Session, window: _Window, limit: int) -> list[TopEntryOut]:
    stmt = window.apply(
        select(
            MusicTrack.name,
            MusicArtist.name,
            func.coalesce(MusicTrack.image_url, MusicArtist.image_url),
            func.count().label("plays"),
            func.sum(MusicPlay.ms_played).label("ms"),
        )
        .join_from(MusicPlay, MusicTrack, MusicPlay.track_id == MusicTrack.id)
        .join(MusicArtist, MusicTrack.artist_id == MusicArtist.id)
        .group_by(MusicTrack.id)
        .order_by(func.count().desc(), func.sum(MusicPlay.ms_played).desc())
        .limit(limit)
    )
    return [
        TopEntryOut(
            rank=i + 1,
            name=row[0],
            artist=row[1],
            image_url=row[2],
            plays=int(row[3]),
            ms=int(row[4] or 0),
        )
        for i, row in enumerate(session.execute(stmt))
    ]


def _top_artists(session: Session, window: _Window, limit: int) -> list[TopEntryOut]:
    stmt = window.apply(
        select(
            MusicArtist.name,
            MusicArtist.image_url,
            func.count().label("plays"),
            func.sum(MusicPlay.ms_played).label("ms"),
        )
        .join_from(MusicPlay, MusicTrack, MusicPlay.track_id == MusicTrack.id)
        .join(MusicArtist, MusicTrack.artist_id == MusicArtist.id)
        .group_by(MusicArtist.id)
        .order_by(func.count().desc(), func.sum(MusicPlay.ms_played).desc())
        .limit(limit)
    )
    return [
        TopEntryOut(
            rank=i + 1,
            name=row[0],
            artist=None,
            image_url=row[1],
            plays=int(row[2]),
            ms=int(row[3] or 0),
        )
        for i, row in enumerate(session.execute(stmt))
    ]


def top(session: Session, kind: str, range_key: str, limit: int) -> list[TopEntryOut]:
    window = _Window(start=_range_start(range_key))
    if kind == "tracks":
        return _top_tracks(session, window, limit)
    if kind == "artists":
        return _top_artists(session, window, limit)
    raise Invalid("kind must be one of: tracks, artists")


def months(session: Session) -> list[MonthOut]:
    """One line per month with anything on it, newest first: how much, and
    who owned it."""
    totals = session.execute(
        select(_IST_MONTH.label("m"), func.count(), func.sum(MusicPlay.ms_played))
        .group_by("m")
        .order_by(_IST_MONTH.desc())
    ).all()
    out: list[MonthOut] = []
    for month_key, plays, ms in totals:
        window = _Window(month=month_key)
        tracks = _top_tracks(session, window, 1)
        artists = _top_artists(session, window, 1)
        out.append(
            MonthOut(
                month=month_key,
                plays=int(plays),
                ms=int(ms or 0),
                top_track=_month_top(tracks),
                top_artist=_month_top(artists),
            )
        )
    return out


def _month_top(entries: list[TopEntryOut]) -> MonthTopOut | None:
    if not entries:
        return None
    e = entries[0]
    return MonthTopOut(name=e.name, artist=e.artist, image_url=e.image_url, plays=e.plays)


def month_detail(session: Session, month: dt.date) -> MonthDetailOut:
    key = f"{month.year:04d}-{month.month:02d}"
    window = _Window(month=key)
    plays, ms = _plays_and_ms(session, window.apply(select(MusicPlay)))
    return MonthDetailOut(
        month=key,
        plays=plays,
        ms=ms,
        tracks=_top_tracks(session, window, 10),
        artists=_top_artists(session, window, 5),
    )


def now(session: Session, cfg: Settings) -> NowOut:
    """The live tile. Every failure shape is just 'nothing playing' — the
    screen never shows an error for a tile that is pure garnish."""
    quiet = NowOut(playing=False)
    try:
        token = _access_token(session, cfg)
        if token is None:
            return quiet
        body = spotify.currently_playing(token)
    except (spotify.SpotifyError, Invalid):
        return quiet
    if body is None or spotify.jget(body, "is_playing") is not True:
        return quiet
    item = spotify.jget(body, "item")
    if item is None:
        return quiet
    images = spotify.jlist(spotify.jget(item, "album"), "images")
    item_artists = spotify.jlist(item, "artists")
    return NowOut(
        playing=True,
        track=spotify.jstr(item, "name"),
        artist=spotify.jstr(item_artists[0], "name") if item_artists else None,
        image_url=spotify.jstr(images[0], "url") if images else None,
        progress_ms=spotify.jint(body, "progress_ms"),
        duration_ms=spotify.jint(item, "duration_ms"),
    )
