import json
from pathlib import Path
from typing import Annotated

import typer
import uvicorn
from sqlalchemy.orm import Session, sessionmaker

from budgetbox.core.config import settings
from budgetbox.db.engine import make_engine
from budgetbox.db.migrate import make_revision, upgrade_to_head
from budgetbox.db.session import make_session_factory

app = typer.Typer(help="BudgetBox backend.", no_args_is_help=True, add_completion=False)
db_app = typer.Typer(help="Database migrations.", no_args_is_help=True)
token_app = typer.Typer(help="Device tokens.", no_args_is_help=True)
jobs_app = typer.Typer(help="Scheduled jobs.", no_args_is_help=True)
app.add_typer(db_app, name="db")
app.add_typer(token_app, name="token")
app.add_typer(jobs_app, name="jobs")


@app.command()
def serve() -> None:
    """Migrate to head, run the daily catch-up once (safety net if the timer
    missed), then run the API server (loopback bind; Caddy fronts it)."""
    from budgetbox.jobs.daily import run_daily

    cfg = settings()
    upgrade_to_head(cfg.db_url)
    run_daily(_session_factory())
    uvicorn.run("budgetbox.api.app:create_app", factory=True, host=cfg.host, port=cfg.port)


@app.command()
def openapi(
    out: Annotated[Path, typer.Option(help="Where to write the spec.")] = Path("openapi.json"),
) -> None:
    """Export the OpenAPI spec — the wiring contract for the Dart client."""
    from budgetbox.api.app import create_app

    spec = create_app().openapi()
    out.write_text(json.dumps(spec, indent=2, sort_keys=True))
    typer.echo(f"wrote {out}")


@db_app.command()
def upgrade() -> None:
    """Apply migrations up to head."""
    upgrade_to_head(settings().db_url)
    typer.echo("database at head")


@db_app.command()
def revision(message: Annotated[str, typer.Argument(help="Migration message.")]) -> None:
    """Autogenerate a migration. Hand-review the diff before it lands."""
    make_revision(settings().db_url, message)


def _session_factory() -> sessionmaker[Session]:
    engine = make_engine(settings().db_path)
    return make_session_factory(engine)


@token_app.command()
def issue(
    label: Annotated[str, typer.Argument(help="What device this token is for.")] = "phone",
) -> None:
    """Mint a device token. The plaintext is printed once and never stored."""
    from budgetbox.modules.tokens import service

    with _session_factory()() as session:
        row, raw = service.issue(session, label)
    typer.echo(f"token id : {row.id}")
    typer.echo(f"label    : {row.label}")
    typer.echo(f"token    : {raw}")
    typer.echo("Store it now — it cannot be shown again.")


@token_app.command("list")
def list_() -> None:
    from budgetbox.modules.tokens import service

    with _session_factory()() as session:
        for row in service.list_tokens(session):
            state = "revoked" if row.revoked_at else "active"
            last = row.last_used_at.isoformat() if row.last_used_at else "never"
            typer.echo(f"{row.id}  {row.label:<20} {state:<8} last used {last}")


@token_app.command()
def revoke(token_id: Annotated[str, typer.Argument(help="Token id to revoke.")]) -> None:
    from budgetbox.modules.tokens import service

    with _session_factory()() as session:
        row = service.revoke(session, token_id)
    typer.echo(f"revoked {row.id} ({row.label})")


@jobs_app.command()
def daily() -> None:
    """Run the daily catch-up jobs (recurring materialization, balance snapshots)."""
    from budgetbox.jobs.daily import run_daily

    upgrade_to_head(settings().db_url)
    ok = run_daily(_session_factory())
    raise typer.Exit(0 if ok else 1)


@app.command("export-csv")
def export_csv(
    out: Annotated[Path, typer.Option(help="Where to write the CSV.")] = Path("budgetbox-txns.csv"),
) -> None:
    """Write the full txn ledger as CSV."""
    from budgetbox.modules.export.csv_export import txns_csv

    with _session_factory()() as session:
        out.write_text(txns_csv(session))
    typer.echo(f"wrote {out}")


@app.command()
def backup(
    out_dir: Annotated[Path, typer.Option(help="Directory for the backup file.")] = Path("."),
) -> None:
    """Consistent logical backup via VACUUM INTO (safe while serving). Encrypt with
    age before it leaves the box — see deploy/runbook."""
    from datetime import UTC, datetime

    from sqlalchemy import text as sql_text

    from budgetbox.db.engine import make_engine

    stamp = datetime.now(UTC).strftime("%Y%m%d-%H%M%S")
    target = out_dir / f"budgetbox-{stamp}.db"
    engine = make_engine(settings().db_path)
    with engine.connect() as conn:
        conn.execute(sql_text("VACUUM INTO :path"), {"path": str(target)})
    typer.echo(f"wrote {target}")


@jobs_app.command("rebuild-snapshots")
def rebuild_snapshots() -> None:
    """Re-derive every balance snapshot from anchors + ledger (exact, safe, slow-ish).
    Use after bulk-editing old history."""
    from budgetbox.modules.networth import service as networth_service

    upgrade_to_head(settings().db_url)
    with _session_factory()() as session:
        written = networth_service.snapshot_all(session, rebuild=True)
    typer.echo(f"rewrote {written} snapshot(s)")


def main() -> None:
    app()
