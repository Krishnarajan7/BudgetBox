"""The thin Spotify client: PKCE handshake, token refresh, and the three
reads this module lives on (recently played, currently playing, an artist's
portrait). Nothing here touches the database — the service owns state.

Spotify's API shrank hard in 2024-2026 (audio features, browse, batch fetches
all gone for new apps); everything used here is on the surviving surface, in
Development Mode, single user. The one operational requirement is that the
account keeps Spotify Premium — a lapsed subscription stops the app cold.

The `j*` helpers are the typed vocabulary for Spotify's JSON: every field is
pulled through one of them, so an odd shape becomes None instead of a crash
mid-poll."""

import base64
import hashlib
import secrets
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import cast
from urllib.parse import urlencode

import httpx

from budgetbox.core.time import now_utc

AUTH_URL = "https://accounts.spotify.com/authorize"
TOKEN_URL = "https://accounts.spotify.com/api/token"
API = "https://api.spotify.com/v1"

# Minimal on purpose: the log of plays and the live tile. Tops are computed
# from our own record, not asked of Spotify.
SCOPES = "user-read-recently-played user-read-currently-playing"

_TIMEOUT = httpx.Timeout(15.0)


class SpotifyError(Exception):
    """Spotify said no, or said something unreadable."""

    def __init__(self, detail: str) -> None:
        super().__init__(detail)
        self.detail = detail


# ————— reading JSON without trusting it —————


def jget(obj: object, key: str) -> object:
    if isinstance(obj, dict):
        return cast(dict[str, object], obj).get(key)
    return None


def jstr(obj: object, key: str) -> str | None:
    value = jget(obj, key)
    return value if isinstance(value, str) else None


def jint(obj: object, key: str) -> int | None:
    value = jget(obj, key)
    return value if isinstance(value, int) and not isinstance(value, bool) else None


def jlist(obj: object, key: str) -> list[object]:
    value = jget(obj, key)
    return cast(list[object], value) if isinstance(value, list) else []


# ————— the handshake —————


@dataclass(frozen=True)
class TokenSet:
    access_token: str
    refresh_token: str | None
    expires_at: datetime


def make_pkce() -> tuple[str, str, str]:
    """(state, verifier, challenge) for one authorization attempt."""
    state = secrets.token_urlsafe(24)
    verifier = secrets.token_urlsafe(64)[:128]
    digest = hashlib.sha256(verifier.encode("ascii")).digest()
    challenge = base64.urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")
    return state, verifier, challenge


def authorize_url(client_id: str, redirect_uri: str, state: str, challenge: str) -> str:
    query = urlencode(
        {
            "response_type": "code",
            "client_id": client_id,
            "scope": SCOPES,
            "redirect_uri": redirect_uri,
            "state": state,
            "code_challenge_method": "S256",
            "code_challenge": challenge,
        }
    )
    return f"{AUTH_URL}?{query}"


def _token_request(form: dict[str, str]) -> TokenSet:
    try:
        response = httpx.post(TOKEN_URL, data=form, timeout=_TIMEOUT)
    except httpx.HTTPError as exc:
        raise SpotifyError(f"token endpoint unreachable: {exc}") from exc
    if response.status_code != 200:
        raise SpotifyError(f"token endpoint said {response.status_code}: {response.text[:200]}")
    body: object = response.json()
    access = jstr(body, "access_token")
    if access is None:
        raise SpotifyError("token response carried no access_token")
    return TokenSet(
        access_token=access,
        refresh_token=jstr(body, "refresh_token"),
        expires_at=now_utc() + timedelta(seconds=jint(body, "expires_in") or 3600),
    )


def exchange_code(client_id: str, redirect_uri: str, code: str, verifier: str) -> TokenSet:
    return _token_request(
        {
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirect_uri,
            "client_id": client_id,
            "code_verifier": verifier,
        }
    )


def refresh_tokens(client_id: str, refresh_token: str) -> TokenSet:
    """Spotify may rotate the refresh token; the caller stores whatever comes back."""
    return _token_request(
        {
            "grant_type": "refresh_token",
            "refresh_token": refresh_token,
            "client_id": client_id,
        }
    )


# ————— the three reads —————


def _get(access_token: str, path: str, params: dict[str, str] | None = None) -> object:
    try:
        response = httpx.get(
            f"{API}{path}",
            params=params,
            headers={"Authorization": f"Bearer {access_token}"},
            timeout=_TIMEOUT,
        )
    except httpx.HTTPError as exc:
        raise SpotifyError(f"api unreachable: {exc}") from exc
    if response.status_code == 204:
        return None
    if response.status_code != 200:
        raise SpotifyError(f"{path} said {response.status_code}: {response.text[:200]}")
    return cast(object, response.json())


def recently_played(access_token: str, after_ms: int | None) -> list[object]:
    """Up to 50 plays newer than the cursor — the whole window Spotify offers.
    The poll exists to outrun it."""
    params = {"limit": "50"}
    if after_ms is not None:
        params["after"] = str(after_ms)
    return jlist(_get(access_token, "/me/player/recently-played", params), "items")


def currently_playing(access_token: str) -> object:
    """The live tile; None when the room is quiet (Spotify sends 204)."""
    return _get(access_token, "/me/player/currently-playing")


def artist_image(access_token: str, spotify_id: str) -> str | None:
    """The largest portrait Spotify has for an artist, if any."""
    images = jlist(_get(access_token, f"/artists/{spotify_id}"), "images")
    return jstr(images[0], "url") if images else None
