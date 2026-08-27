from datetime import datetime

from pydantic import Field

from budgetbox.api.schemas import APIModel


class OverviewOut(APIModel):
    connected: bool
    # The very first play on record (import reaches years further back than
    # the poll) — null until anything has been heard.
    since: datetime | None
    # When the half-hour poll started keeping the book; the honest boundary
    # between "recorded live" and "recovered from the export".
    recording_since: datetime | None
    total_plays: int
    total_ms: int
    distinct_tracks: int
    distinct_artists: int
    this_month_plays: int
    this_month_ms: int


class TopEntryOut(APIModel):
    rank: int
    name: str
    # The performer, when the entry is a track; null on artist entries.
    artist: str | None
    image_url: str | None
    plays: int
    ms: int


class MonthTopOut(APIModel):
    name: str
    artist: str | None
    image_url: str | None
    plays: int


class MonthOut(APIModel):
    month: str = Field(pattern=r"^\d{4}-\d{2}$")
    plays: int
    ms: int
    top_track: MonthTopOut | None
    top_artist: MonthTopOut | None


class MonthDetailOut(APIModel):
    month: str = Field(pattern=r"^\d{4}-\d{2}$")
    plays: int
    ms: int
    tracks: list[TopEntryOut]
    artists: list[TopEntryOut]


class NowOut(APIModel):
    playing: bool
    track: str | None = None
    artist: str | None = None
    image_url: str | None = None
    progress_ms: int | None = None
    duration_ms: int | None = None


class ConnectOut(APIModel):
    # The Spotify consent page: open it in any browser, once.
    url: str
