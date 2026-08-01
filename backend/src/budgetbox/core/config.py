from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Process configuration. Reads BBX_* env vars, then .env; explicit args win in tests."""

    model_config = SettingsConfigDict(env_prefix="bbx_", env_file=".env", extra="ignore")

    env: Literal["dev", "prod"] = "dev"
    db_path: Path = Path("budgetbox.db")
    log_level: str = "INFO"
    host: str = "127.0.0.1"
    port: int = 8000

    @property
    def db_url(self) -> str:
        return f"sqlite:///{self.db_path}"


@lru_cache
def settings() -> Settings:
    return Settings()
