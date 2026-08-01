"""Programmatic Alembic entrypoints — the CLI and tests share one code path,
so every test run validates the migration chain from an empty database."""

from pathlib import Path

from alembic import command
from alembic.config import Config

_MIGRATIONS_DIR = Path(__file__).parent / "migrations"


def alembic_config(db_url: str) -> Config:
    cfg = Config()
    cfg.set_main_option("script_location", str(_MIGRATIONS_DIR))
    cfg.set_main_option("sqlalchemy.url", db_url)
    return cfg


def upgrade_to_head(db_url: str) -> None:
    command.upgrade(alembic_config(db_url), "head")


def make_revision(db_url: str, message: str) -> None:
    """Autogenerate a revision; the diff must be hand-reviewed before it lands."""
    command.revision(alembic_config(db_url), message=message, autogenerate=True)
