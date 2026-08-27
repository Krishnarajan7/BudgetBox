# Connecting Spotify (one time), and the music book on the VPS

The music book lives entirely on the server. Spotify's API only ever shows the
**last 50 plays** — a rolling window, no history endpoint — so the backend polls
that window every half hour and keeps what Spotify drops. The phone only reads
`/v1/music/*`; it never talks to Spotify.

## Facts this runbook assumes

| Thing | Value |
|---|---|
| Server | `187.127.186.27` (`bbx.zentumapp.in`), Ubuntu 24.04 |
| Code | `/opt/budgetbox/backend` (rsync'd from the Mac, **not** git) |
| Env | `/etc/budgetbox/env` (a systemd `EnvironmentFile`) |
| Service user | `budgetbox` |
| API bind | `127.0.0.1:8787`, nginx vhost `bbx.zentumapp.in` |
| Redirect URI | `https://bbx.zentumapp.in/spotify/callback` |

## Never call the CLI directly on the VPS

`/etc/budgetbox/env` is a systemd `EnvironmentFile` — systemd loads it for the
units and for **nothing else**. A CLI command run by hand sees none of it, and
`db_path` defaults to a *relative* `budgetbox.db`, so the command silently opens
a new empty database in the working directory. An import run that way would pour
years of history into a file nothing ever reads.

Use the wrapper, which sources the env, refuses to run without `BBX_DB_PATH`, and
drops to the `budgetbox` user:

```bash
sudo /opt/budgetbox/backend/deploy/bbx.sh <command…>
```

## 1. Ship the code (from the Mac)

```bash
cd ~/Projects/BudgetBox
rsync -av --delete \
  --exclude .venv --exclude __pycache__ --exclude '.pytest_cache' \
  --exclude '.ruff_cache' --exclude '*.db' \
  backend/ root@187.127.186.27:/opt/budgetbox/backend/
```

## 2. Add the two Spotify variables (on the VPS)

`BBX_SPOTIFY_CLIENT_ID` is the Client ID from the Spotify dashboard. There is no
client secret — the handshake is PKCE.

```bash
sudo tee -a /etc/budgetbox/env >/dev/null <<'ENV'
BBX_SPOTIFY_CLIENT_ID=PASTE_YOUR_CLIENT_ID_HERE
BBX_SPOTIFY_REDIRECT_URI=https://bbx.zentumapp.in/spotify/callback
ENV
```

The redirect URI must match what is registered on the Spotify app
character-for-character: `https://`, no trailing slash, no port.

## 3. Deps, migration, restart

```bash
cd /opt/budgetbox/backend
sudo -u budgetbox /usr/local/bin/uv sync --frozen
sudo deploy/bbx.sh db upgrade          # applies migration 0014 (the music tables)
sudo systemctl restart budgetbox
curl -fsS http://127.0.0.1:8787/healthz && echo
```

## 4. Install the half-hour poll timer

50 plays is roughly three hours of continuous listening, so a 30-minute cadence
has about 6x headroom before the window can roll anything away.

```bash
cd /opt/budgetbox/backend
sudo cp deploy/budgetbox-music.service deploy/budgetbox-music.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now budgetbox-music.timer
systemctl list-timers budgetbox-music.timer
```

## 5. The handshake

```bash
sudo deploy/bbx.sh music connect-url
```

Open the printed URL in any browser, approve, and it lands on
`https://bbx.zentumapp.in/spotify/callback` reading **"Spotify is connected."**
The handshake expires after 10 minutes — if you dawdle, just run it again.

Confirm the recorder is alive:

```bash
sudo deploy/bbx.sh music poll     # → "recorded N play(s), M portrait(s)"
```

Play something on Spotify, wait a minute, run it again and the number moves.

## 6. The backfill, when the export arrives

Request it at <https://www.spotify.com/account/privacy/> — tick **only**
"Extended streaming history". It can take up to 30 days. When the zip arrives,
unpack it and copy the folder of `Streaming_History_Audio_*.json` files to the
VPS:

```bash
scp -r ~/Downloads/my_spotify_data root@187.127.186.27:/tmp/spotify-export
sudo deploy/bbx.sh music import /tmp/spotify-export
```

Idempotent, so re-running it is safe. It skips plays under 30 seconds, podcasts,
and anything at or after the first *polled* play — the live record wins where the
two overlap, which is what stops every overlapping play being counted twice.

## Operational notes

- **Spotify Premium is required.** Since February 2026 a Development Mode app
  stops working if the owner's Premium lapses. The poll will start failing with
  auth errors until it is reactivated; `journalctl -u budgetbox-music` shows it.
- The poll is a catch-up job. If the box is down for a day it simply resumes —
  though anything Spotify rolled out of the 50-play window in the meantime is
  genuinely gone.
- `deploy/deploy.sh` is stale: it assumes `git pull` and port 8000. The real flow
  is the rsync above and port 8787.
- Health of the recorder: `systemctl status budgetbox-music.timer` and
  `journalctl -u budgetbox-music -n 50`.
