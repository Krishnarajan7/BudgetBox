# BudgetBox backend

Single-user personal ledger API — the source of truth the Flutter app will be
wired to. FastAPI + SQLAlchemy 2.0 + SQLite (WAL), Python 3.13, managed by uv.

## Layout

```
src/budgetbox/
  core/      config, IST time rules, money (int paise), uuid7 ids, error slugs
  domain/    PURE math: FY/salary periods, budget pace, recurrence, insights, events
  db/        engine (WAL pragmas), typed columns, Alembic migrations
  modules/   one package per feature: models / schemas / service / router
  api/       app factory, bearer auth, problem+json, pagination
  jobs/      idempotent daily catch-up (recurring materialization, snapshots)
deploy/      Caddyfile, systemd units, litestream.yml, deploy + backup scripts
tests/       unit (domain), integration (API + real SQLite via migrations), golden
```

Iron rules: money is always integer paise; calendar days are IST and only
`core.time.day_key` converts an instant to a day; `domain/` imports no framework;
services own transactions (`session.commit()`), routers own nothing.

## Local development

```bash
cd backend
uv sync                 # installs Python 3.13 + deps into .venv
uv run pytest           # full suite (schema built via real migrations)
uv run ruff format . && uv run ruff check . && uv run pyright
uv run budgetbox --help
```

Quality gate before any change lands: `ruff` + `pyright` + `pytest`, all green.

Run a dev server (DB path via `BBX_DB_PATH`, defaults to ./budgetbox.db):

```bash
uv run budgetbox serve                    # migrates, runs daily jobs, serves :8000
uv run budgetbox token issue phone        # prints bbx_... once; store it
curl -H "Authorization: Bearer bbx_..." localhost:8000/v1/ping
```

## API shape

- `/v1/*`, JSON, snake_case. Auth: `Authorization: Bearer bbx_...` (single
  pre-provisioned device token; no signup). `/healthz` is open.
- Writes are idempotent `PUT /v1/{resource}/{client-generated-uuid7}` — the phone
  can queue offline and retry blindly. Partial edits via `PATCH`.
- Errors are RFC 9457 `application/problem+json` with stable
  `urn:budgetbox:problem:<slug>` types.
- Derived read models are first-class, and shaped by screen so the phone gets a
  page in one call: `/v1/summary/{today,month,calendar}`, `/v1/budgets/pace`,
  `/v1/budgets/{id}/trail`, `/v1/pinned/board`, `/v1/recurring/upcoming`,
  `/v1/goals`, `/v1/networth/{current,series,accounts}`,
  `/v1/insights/month-story`, `/v1/focus/stats`, `/v1/journal/month`,
  `/v1/journal/{day}/facts`, `/v1/changes?since=`.
- The add sheet's five-second path has its own memory endpoints:
  `/v1/txns/suggest`, `/v1/txns/recent-amounts`, `/v1/categories/top`.
- Plan workflows are server-side and atomic: `POST /v1/budgets/rebalance`,
  `GET /v1/budgets/suggestions`, and retry-safe manual recurring payments at
  `PUT /v1/recurring/{recurring_id}/payments/{txn_id}`.
- `uv run budgetbox openapi` exports `openapi.json` — the contract for generating
  the Dart client when the screens are ready to wire.

## Data rules worth knowing

- **Balances are derived**, never stored: latest user-confirmed anchor
  (`POST /v1/accounts/{id}/anchors`) + signed txn deltas after it. Undo needs no
  compensating writes; drift is structurally impossible.
- **Txn mutations log an Activity snapshot** in the same transaction;
  `POST /v1/activities/{id}/undo` replays the inverse and consumes the row.
- **Recurrings materialize** via the daily job — catch-up idempotent, so downtime
  self-heals; a partial unique index guarantees one txn per (recurring, due).
- **Net worth history** is a rebuildable cache (`account_snapshots`): the last 90
  days re-derive every run; `budgetbox jobs rebuild-snapshots` redoes all of it.
- **Vault is zero-knowledge**: opaque nonce+cipher blobs only, never logged.
- **Sealing a day is a ritual, not a ledger fact.** `PUT /v1/seals/{day}` closes a
  page and `DELETE` reopens it; both are idempotent and neither leaves a trace,
  because taking it back is allowed to cost nothing.
- **The book stays quiet without evidence.** Conditional story pages, the journal's
  mood-against-money line and the "held its line N months running" streak all
  return null/zero rather than a guess: a blank month is silence, not restraint.

## VPS runbook (Ubuntu-ish)

1. `adduser budgetbox`, install uv, Caddy, Litestream, age; `ufw allow 22,80,443`.
2. Clone to `/opt/budgetbox`, `uv sync --frozen` in `backend/`.
3. Config: `/etc/budgetbox/env` (chmod 600) with `BBX_ENV=prod`,
   `BBX_DB_PATH=/var/lib/budgetbox/budgetbox.db`, Litestream bucket creds.
4. Install units from `deploy/`: `budgetbox.service`, `budgetbox-daily.timer`
   (00:05 IST), `litestream.service`; Caddyfile with your domain.
5. `uv run budgetbox token issue phone` — put the token in the app when wiring.
6. Deploys: `deploy/deploy.sh`. Nightly encrypted backup: `deploy/nightly-backup.sh`
   (age public key on the VPS; the private key stays on the Mac).
7. **Restore drill** (do this once now, not during a fire):
   `litestream restore -o restored.db /var/lib/budgetbox/budgetbox.db` or
   `age -d -i key.txt backup.age > restored.db`, then point `BBX_DB_PATH` at it
   and check `/healthz` + a few reads.

## Migrations

`uv run budgetbox db revision "message"` autogenerates into
`src/budgetbox/db/migrations/versions/` — hand-review every diff, keep one linear
head, sequential ids (0001, 0002, …). Tests always build the schema from the
migration chain, so a broken migration fails the suite immediately.
